import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pwa/models/app_user.dart';
import 'package:pwa/supabase/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService extends ChangeNotifier {
  static const Duration _authTimeout = Duration(seconds: 20);

  static const _prefsKeyPinEnabled = 'auth.pin_enabled';
  static const _prefsKeyLastEmail = 'auth.last_email';
  static const _prefsKeySavedPasswordPrefix = 'auth.saved_password.';

  bool _isInitialized = false;
  bool _isLoading = false;
  AppUser? _currentUser;
  late final StreamSubscription<AuthState> _authSub;

  bool _pinEnabled = false;
  String? _lastEmail;

  // When doing a PIN login, Supabase will create a session *before* we can verify
  // the PIN via RPC. If we let our auth listener eagerly set `_currentUser`, the
  // router may redirect into the app even when the PIN is wrong.
  //
  // This flag makes PIN login atomic: we only publish a signed-in user after
  // PIN verification succeeds.
  bool _holdProfileUntilPinVerified = false;

  Future<void> _waitForSessionReady({required String expectedUserId}) async {
    // Supabase can complete `signInWithPassword` before the PostgREST client
    // has fully picked up the new access token for subsequent RPC calls.
    // This shows up as RPCs behaving like an anonymous request (auth.uid() = null)
    // which makes `verify_user_pin` return false even for a correct PIN.
    const maxAttempts = 12;
    for (var i = 0; i < maxAttempts; i++) {
      final session = SupabaseConfig.auth.currentSession;
      final user = SupabaseConfig.auth.currentUser;
      final token = session?.accessToken ?? '';
      if (user?.id == expectedUserId && token.trim().isNotEmpty) return;
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
    debugPrint('AuthService: session not ready after wait (expectedUserId=$expectedUserId).');
  }

  void _logRpcValue(String label, dynamic value) {
    debugPrint('$label: type=${value.runtimeType} value=$value');
    if (value is Map) debugPrint('$label: keys=${value.keys.toList()}');
    if (value is List) debugPrint('$label: length=${value.length}');
  }

  Future<bool> _verifyPinViaRpcWithRetry({required String pin, required String expectedUserId}) async {
    // We retry because immediately after sign-in, the first PostgREST call can
    // sometimes behave like an anonymous request (auth.uid() null) and return false.
    const attempts = 3;
    for (var i = 0; i < attempts; i++) {
      await _waitForSessionReady(expectedUserId: expectedUserId);
      final okRes = await SupabaseConfig.client.rpc('verify_user_pin', params: {'pin_input': pin.trim()});
      _logRpcValue('AuthService._verifyPinViaRpcWithRetry attempt=${i + 1} raw response', okRes);
      final ok = _parseRpcBool(okRes, key: 'verify_user_pin');
      if (ok) return true;
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    return false;
  }

  bool _parseRpcBool(dynamic value, {String? key}) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final v = value.trim().toLowerCase();
      if (v == 't') return true;
      if (v == 'f') return false;
      if (v == 'true') return true;
      if (v == 'false') return false;
      final n = num.tryParse(v);
      if (n != null) return n != 0;
    }

    // Supabase Dart versions can return RPC results wrapped.
    // Common shapes:
    // - {"data": true}
    // - {"data": {"verify_user_pin": true}}
    // - [{"verify_user_pin": true}]
    // - [true]
    if (value is Map) {
      if (value.containsKey('data')) return _parseRpcBool(value['data'], key: key);
      if (key != null && value.containsKey(key)) return _parseRpcBool(value[key]);
      // If it's a single-entry map, treat its only value as the scalar.
      if (value.length == 1) return _parseRpcBool(value.values.first, key: key);
    }

    if (value is List) {
      if (value.isEmpty) return false;
      if (value.length == 1) return _parseRpcBool(value.first, key: key);
      if (key != null) {
        final first = value.first;
        if (first is Map && first.containsKey(key)) return _parseRpcBool(first[key]);
      }
    }

    // Some PostgREST/Supabase client versions can wrap scalar RPC outputs.
    // Example shapes we defensively support:
    // - {"verify_user_pin": true}
    // - [{"verify_user_pin": true}]
    return false;
  }

  Future<void> _revokeSessionAfterFailedPin() async {
    // Best-effort: if we created a Supabase session (via password) but PIN failed,
    // we must revoke it immediately so the router cannot treat the user as authenticated.
    try {
      await SupabaseConfig.auth.signOut();
    } catch (e) {
      debugPrint('AuthService: failed to sign out after PIN failure: $e');
    } finally {
      // Keep holding until the auth stream delivers the signed-out event.
      // (The listener will clear state and release the hold.)
      _currentUser = null;
      notifyListeners();
    }
  }

  Future<bool> _isPinHashMissingForUser(String userId) async {
    try {
      final row = await SupabaseService.selectSingle(
        'users',
        select: 'pin_hash',
        filters: {'id': userId},
      );
      if (row == null) return true;
      final v = row['pin_hash'];
      if (v == null) return true;
      final s = v.toString().trim();
      return s.isEmpty;
    } catch (e) {
      // If RLS blocks access (or network issues), we can't safely auto-repair.
      debugPrint('AuthService: unable to read pin_hash (possible RLS): $e');
      return false;
    }
  }

  Future<bool> _tryRepairMissingPinHash({required User supaUser, required String pin}) async {
    // Self-heal for the common case where signup succeeded but `set_user_pin` failed
    // (e.g., pin_hash column was missing at the time). We only do this if we can
    // confirm the current row has no pin_hash.
    final missing = await _isPinHashMissingForUser(supaUser.id);
    if (!missing) return false;

    try {
      debugPrint('AuthService: pin_hash missing; attempting to set PIN now.');
      await SupabaseConfig.client.rpc('set_user_pin', params: {'pin_input': pin.trim()});
      final okRes = await SupabaseConfig.client.rpc('verify_user_pin', params: {'pin_input': pin.trim()});
      _logRpcValue('AuthService._tryRepairMissingPinHash verify_user_pin raw response', okRes);
      final ok = _parseRpcBool(okRes, key: 'verify_user_pin');
      return ok;
    } catch (e) {
      debugPrint('AuthService: failed to repair missing pin_hash: $e');
      return false;
    }
  }

  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;
  AppUser? get currentUser => _currentUser;
  bool get isSignedIn => _currentUser != null;

  bool get pinEnabled => _pinEnabled;
  String? get lastEmail => _lastEmail;

  Future<void> init() async {
    if (_isInitialized) return;
    _isLoading = true;
    notifyListeners();
    try {
      await _loadPrefs();

      _authSub = SupabaseConfig.auth.onAuthStateChange.listen((event) async {
        final supaUser = event.session?.user;
        if (supaUser == null) {
          // Defensive: if we were in the middle of any auth flow (sign-out, token refresh,
          // failed PIN verification, etc.) and ended up signed-out, ensure we don't leave
          // the app in a permanent "loading" state. This directly prevents the Welcome
          // screen from getting stuck on "Please wait…" and disabling all taps.
          _isLoading = false;
          _holdProfileUntilPinVerified = false;
          _currentUser = null;
          notifyListeners();
          return;
        }

        // During PIN sign-in we intentionally suppress publishing an authenticated
        // profile until the RPC verifies the PIN.
        if (_holdProfileUntilPinVerified) return;

        try {
          _currentUser = await _loadOrCreateProfile(supaUser, displayNameHint: null);
          _lastEmail = (supaUser.email ?? '').trim().toLowerCase();
          await _savePrefs();
        } catch (e) {
          debugPrint('AuthService: failed to load profile: $e');
        }
        notifyListeners();
      });

      final existing = SupabaseConfig.auth.currentUser;
      if (existing != null) {
        _currentUser = await _loadOrCreateProfile(existing, displayNameHint: null);
        _lastEmail = (existing.email ?? '').trim().toLowerCase();
      }
    } catch (e) {
      debugPrint('AuthService.init failed: $e');
    } finally {
      _isInitialized = true;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _pinEnabled = prefs.getBool(_prefsKeyPinEnabled) ?? false;
      _lastEmail = prefs.getString(_prefsKeyLastEmail);
    } catch (e) {
      debugPrint('AuthService: failed to load prefs: $e');
      _pinEnabled = false;
      _lastEmail = null;
    }
  }

  Future<void> _savePrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKeyPinEnabled, _pinEnabled);
      if (_lastEmail != null) await prefs.setString(_prefsKeyLastEmail, _lastEmail!);
    } catch (e) {
      debugPrint('AuthService: failed to save prefs: $e');
    }
  }

  String _passwordKeyForEmail(String email) => '$_prefsKeySavedPasswordPrefix${email.trim().toLowerCase()}';

  Future<void> _savePasswordForEmail({required String email, required String password}) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty || password.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_passwordKeyForEmail(normalized), password);
    } catch (e) {
      debugPrint('AuthService: failed to save password for email: $e');
    }
  }

  Future<String?> _getSavedPasswordForEmail(String email) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_passwordKeyForEmail(normalized));
    } catch (e) {
      debugPrint('AuthService: failed to read saved password for email: $e');
      return null;
    }
  }

  void _validatePinOrThrow(String pin) {
    final p = pin.trim();
    if (p.length != 4 || p.contains(RegExp(r'\D'))) throw Exception('PIN must be exactly 4 digits.');
  }

  Exception _friendlyPinRpcException(dynamic e) {
    if (e is PostgrestException) {
      // PGRST202: PostgREST schema cache does not have the function/signature.
      if ((e.code ?? '').toString() == 'PGRST202') {
        return Exception(
          'PIN backend is not installed on Supabase yet. Please apply the SQL in lib/supabase/supabase_tables.sql (it creates public.set_user_pin and public.verify_user_pin), then reload the Supabase API schema cache.',
        );
      }
      return Exception(e.message);
    }
    return Exception(e.toString());
  }

  /// Store a PIN hash for the currently authenticated user (requires session).
  Future<void> setPin({required String pin}) async {
    _validatePinOrThrow(pin);
    try {
      await SupabaseConfig.client.rpc('set_user_pin', params: {'pin_input': pin.trim()});
      _pinEnabled = true;
      await _savePrefs();
      notifyListeners();
    } on PostgrestException catch (e) {
      debugPrint('AuthService.setPin failed: ${e.message} (code: ${e.code})');
      throw _friendlyPinRpcException(e);
    } catch (e) {
      debugPrint('AuthService.setPin failed: $e');
      throw _friendlyPinRpcException(e);
    }
  }

  Future<AppUser> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    _isLoading = true;
    notifyListeners();
    try {
      final normalized = email.trim();
      if (normalized.isEmpty || !normalized.contains('@')) throw Exception('Please enter a valid email.');
      _validatePasswordOrThrow(password);

      final res = await SupabaseConfig.auth
          .signUp(
        email: normalized,
        password: password,
        data: {
          // Stored in auth.users.user_metadata (and available as a hint for profile creation).
          'display_name': displayName.trim(),
        },
      ).timeout(_authTimeout);

      final supaUser = res.user;
      if (supaUser == null) throw Exception('Sign up failed. Please try again.');

      // Goal: go straight to dashboard after sign up.
      // Depending on Supabase Auth settings, signUp may or may not create a session.
      // If no session was created, try an immediate email+password sign-in.
      // Note: If your project requires email confirmation, this sign-in will fail and we surface
      // a clear message so you can disable confirmation in Supabase (recommended for this UX).
      final session = SupabaseConfig.auth.currentSession;
      if (session == null) {
        try {
            await SupabaseConfig.auth
                .signInWithPassword(email: normalized, password: password)
                .timeout(_authTimeout);
        } on AuthException catch (e) {
          throw Exception(_friendlyAuthMessage(e));
        }
      }

      final profile = await _loadOrCreateProfile(supaUser, displayNameHint: displayName);
      _currentUser = profile;
      notifyListeners();
      return profile;
    } catch (e) {
      debugPrint('AuthService.register failed: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Primary onboarding flow for this project:
  /// 1) Upsert Xero customer (by email) and get ContactID
  /// 2) Create Supabase Auth user (email+password)
  /// 3) Upsert public.users profile with trade details + Xero ContactID
  /// 4) Save the user's PIN hash via `public.set_user_pin()`
  Future<AppUser> registerTradeAccount({
    required String displayName,
    required String companyName,
    required String email,
    required String phoneNumber,
    required String password,
    required String pin,
  }) async {
    _isLoading = true;
    notifyListeners();
    try {
      final normalizedEmail = email.trim().toLowerCase();
      if (displayName.trim().isEmpty) throw Exception('Please enter your full name.');
      if (companyName.trim().isEmpty) throw Exception('Please enter your company name.');
      if (phoneNumber.trim().isEmpty) throw Exception('Please enter your phone number.');
      if (normalizedEmail.isEmpty || !normalizedEmail.contains('@')) throw Exception('Please enter a valid email.');
      _validatePasswordOrThrow(password);
      _validatePinOrThrow(pin);

      final exists = await emailExists(email: normalizedEmail);
      if (exists) throw Exception('An account already exists with this email. Please sign in instead.');

      // 1) Upsert user in Xero (Edge Function) to get Xero ContactID.
      String xeroContactId;
      try {
        const fnName = 'xero_upsert_contact_cc';
        final debugUrl = SupabaseConfig.edgeFunctionUrl(fnName);
        debugPrint('AuthService.registerTradeAccount: invoking $fnName at $debugUrl');

        final res = await SupabaseConfig.client.functions
            .invoke(
              fnName,
              body: {
                'fullName': displayName.trim(),
                'email': normalizedEmail,
                'companyName': companyName.trim(),
                'phoneNumber': phoneNumber.trim(),
              },
              headers: const {'content-type': 'application/json'},
            )
            .timeout(const Duration(seconds: 18));

        final data = res.data;
        final maybe = (data is Map) ? data['contactId'] : null;
        xeroContactId = (maybe is String) ? maybe.trim() : '';
        if (xeroContactId.isEmpty) {
          debugPrint('AuthService.registerTradeAccount: $fnName unexpected response: ${res.data}');
          throw Exception('Failed to create your Xero account. Please try again.');
        }
      } catch (e) {
        debugPrint('AuthService.registerTradeAccount: Xero upsert failed: $e');
        final msg = e.toString().toLowerCase();
        if (msg.contains('failed to fetch') || msg.contains('clientfailed') || msg.contains('clientexception')) {
          throw Exception(
            'Xero service is unreachable. Please deploy the Edge Function and set its secrets: ${SupabaseConfig.edgeFunctionUrl('xero_upsert_contact_cc')}',
          );
        }
        rethrow;
      }

      // 2) Create Supabase Auth user.
      final res = await SupabaseConfig.auth
          .signUp(
        email: normalizedEmail,
        password: password,
        data: {
          'display_name': displayName.trim(),
        },
      ).timeout(_authTimeout);

      final supaUser = res.user;
      if (supaUser == null) throw Exception('Sign up failed. Please try again.');

      // Ensure we have a session for RPC + table writes.
      final session = SupabaseConfig.auth.currentSession;
      if (session == null) {
        try {
          await SupabaseConfig.auth
              .signInWithPassword(email: normalizedEmail, password: password)
              .timeout(_authTimeout);
        } on AuthException catch (e) {
          throw Exception(_friendlyAuthMessage(e));
        }
      }

      // 3) Upsert the profile row with trade fields.
      try {
        final now = DateTime.now().toUtc().toIso8601String();
        await SupabaseService.from('users').upsert({
          'id': supaUser.id,
          'email': (supaUser.email ?? normalizedEmail).trim(),
          'display_name': displayName.trim(),
          'company_name': companyName.trim(),
          'phone_number': phoneNumber.trim(),
          'xero_account_id': xeroContactId,
          'created_at': now,
          'updated_at': now,
        });
      } on PostgrestException catch (e) {
        debugPrint('AuthService.registerTradeAccount: profile upsert failed: ${e.message} (code: ${e.code})');
        // Don't block onboarding if RLS is misconfigured; profile can still be created by server hooks.
      } catch (e) {
        debugPrint('AuthService.registerTradeAccount: profile upsert failed: $e');
      }

      final profile = await _loadOrCreateProfile(supaUser, displayNameHint: displayName);

      // 4) Save PIN hash (server-side).
      try {
        await _waitForSessionReady(expectedUserId: supaUser.id);
        await SupabaseConfig.client.rpc('set_user_pin', params: {'pin_input': pin.trim()});
        final ok = await _verifyPinViaRpcWithRetry(pin: pin, expectedUserId: supaUser.id);
        if (!ok) throw Exception('PIN could not be saved correctly. Please try again.');

        _pinEnabled = true;
        _lastEmail = normalizedEmail;
        await _savePasswordForEmail(email: normalizedEmail, password: password);
        await _savePrefs();
      } on PostgrestException catch (e) {
        debugPrint('AuthService.registerTradeAccount: set/verify pin failed: ${e.message} (code: ${e.code})');
        throw _friendlyPinRpcException(e);
      } catch (e) {
        debugPrint('AuthService.registerTradeAccount: set/verify pin failed: $e');
        rethrow;
      }

      _currentUser = profile;
      notifyListeners();
      return profile;
    } catch (e) {
      debugPrint('AuthService.registerTradeAccount failed: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Checks whether an Auth user already exists for [email].
  ///
  /// This uses the `check_email_exists` Supabase Edge Function, because the client
  /// cannot directly query `auth.users`.
  Future<bool> emailExists({required String email}) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty || !normalized.contains('@')) throw Exception('Please enter a valid email.');
    try {
      const fnName = 'check_email_exists';
      final debugUrl = SupabaseConfig.edgeFunctionUrl(fnName);
      debugPrint('AuthService.emailExists: invoking $fnName at $debugUrl');

      final res = await SupabaseConfig.client.functions
          .invoke(
            fnName,
            body: {'email': normalized},
            headers: const {'content-type': 'application/json'},
          )
          .timeout(const Duration(seconds: 12));

      final data = res.data;
      if (data is Map) {
        final exists = data['exists'];
        if (exists is bool) return exists;
      }
      debugPrint('AuthService.emailExists: unexpected response: ${res.data}');
      throw Exception('Unable to validate email. Please try again.');
    } catch (e) {
      // On Flutter Web, a missing/un-deployed edge function often surfaces as
      // "ClientFailed to fetch" (CORS/network) rather than a clean 404.
      // Provide an actionable hint.
      debugPrint('AuthService.emailExists failed: $e');
      final msg = e.toString().toLowerCase();
      if (msg.contains('failed to fetch') || msg.contains('clientfailed') || msg.contains('clientexception')) {
        throw Exception(
          'Email check service is unreachable. Please confirm the Edge Function is deployed and CORS is enabled: ${SupabaseConfig.edgeFunctionUrl('check_email_exists')}',
        );
      }
      rethrow;
    }
  }

  Future<void> requestSignupEmailCode({required String email, required String displayName}) async {
    _isLoading = true;
    notifyListeners();
    try {
      final normalized = email.trim();
      if (normalized.isEmpty || !normalized.contains('@')) throw Exception('Please enter a valid email.');

      // Supabase decides whether it sends a magic link or an OTP code based on your Auth settings + templates.
      // This call requests an OTP-based sign-in/signup.
      await SupabaseConfig.auth
          .signInWithOtp(
        email: normalized,
        shouldCreateUser: true,
        data: {
          'display_name': displayName.trim(),
        },
      )
          .timeout(_authTimeout);
    } on AuthException catch (e) {
      debugPrint('AuthService.requestSignupEmailCode auth error: ${e.message}');
      throw Exception(_friendlyAuthMessage(e));
    } catch (e) {
      debugPrint('AuthService.requestSignupEmailCode failed: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<AppUser> verifySignupEmailCode({
    required String email,
    required String displayName,
    required String companyName,
    required String phoneNumber,
    required String password,
    required String code,
    required String pin,
  }) async {
    _isLoading = true;
    notifyListeners();
    try {
      final normalized = email.trim();
      if (normalized.isEmpty || !normalized.contains('@')) throw Exception('Please enter a valid email.');
      final token = code.trim();
      if (token.length != 6 || token.contains(RegExp(r'\D'))) throw Exception('Please enter the 6-digit code.');
      _validatePasswordOrThrow(password);
      _validatePinOrThrow(pin);
      if (companyName.trim().isEmpty) throw Exception('Please enter your company name.');
      if (phoneNumber.trim().isEmpty) throw Exception('Please enter your phone number.');

      final res = await SupabaseConfig.auth
          .verifyOTP(
        type: OtpType.signup,
        email: normalized,
        token: token,
      )
          .timeout(_authTimeout);

      final supaUser = res.user ?? SupabaseConfig.auth.currentUser;
      if (supaUser == null) throw Exception('Verification succeeded, but no user was returned. Please try signing in.');

      // Attach password to the now-authenticated user.
      try {
        await SupabaseConfig.auth
            .updateUser(UserAttributes(
          password: password,
          data: {
            'display_name': displayName.trim(),
          },
        ))
            .timeout(_authTimeout);
      } on AuthException catch (e) {
        debugPrint('AuthService.verifySignupEmailCode updateUser error: ${e.message}');
        throw Exception(_friendlyAuthMessage(e));
      }

      // 1) Upsert user in Xero (server-side Edge Function) to get Xero ContactID.
      String? xeroContactId;
      try {
        // Uses Xero Custom Connection (client_credentials) – no refresh_token required.
        const fnName = 'xero_upsert_contact_cc';
        final debugUrl = SupabaseConfig.edgeFunctionUrl(fnName);
        debugPrint('AuthService.verifySignupEmailCode: invoking $fnName at $debugUrl');

        final res = await SupabaseConfig.client.functions
            .invoke(
              fnName,
              body: {
                'full_name': displayName.trim(),
                'email': normalized.trim().toLowerCase(),
                'company_name': companyName.trim(),
                'phone_number': phoneNumber.trim(),
              },
              headers: const {'content-type': 'application/json'},
            )
            .timeout(const Duration(seconds: 18));

        final data = res.data;
        if (data is Map && data['contactId'] is String) {
          xeroContactId = (data['contactId'] as String).trim();
        }
        if (xeroContactId == null || xeroContactId.isEmpty) {
          debugPrint('AuthService.verifySignupEmailCode: $fnName unexpected response: ${res.data}');
          throw Exception('Failed to create your Xero account. Please try again.');
        }
      } catch (e) {
        debugPrint('AuthService.verifySignupEmailCode: Xero upsert failed: $e');
        final msg = e.toString().toLowerCase();
        if (msg.contains('xero_invalid_scope') || msg.contains('invalid_scope') || msg.contains('no valid scopes remaining')) {
          throw Exception(
            "Xero isn't configured for machine-to-machine sync. Your Xero app must be a Custom Connection (client_credentials) and its scopes must include 'accounting.contacts'. Also ensure your Edge Function secret XERO_SCOPES does NOT include offline_access/openid/profile/email.",
          );
        }
        if (msg.contains('failed to fetch') || msg.contains('clientfailed') || msg.contains('clientexception')) {
          throw Exception(
            'Xero service is unreachable. Please deploy the Edge Function and set its secrets: ${SupabaseConfig.edgeFunctionUrl('xero_upsert_contact_cc')}',
          );
        }
        rethrow;
      }

      // 2) Upsert the profile row (and save the extended fields) to public.users.
      // We do this BEFORE setting the PIN so `public.set_user_pin()` won't fail with
      // "Profile row not found".
      try {
        final now = DateTime.now().toUtc().toIso8601String();
        await SupabaseService.from('users').upsert({
          'id': supaUser.id,
          'email': (supaUser.email ?? normalized).trim(),
          'display_name': displayName.trim(),
          'company_name': companyName.trim(),
          'phone_number': phoneNumber.trim(),
          'xero_account_id': xeroContactId,
          'updated_at': now,
        });
      } on PostgrestException catch (e) {
        debugPrint('AuthService.verifySignupEmailCode: profile update blocked/failed: ${e.message} (code: ${e.code})');
      } catch (e) {
        debugPrint('AuthService.verifySignupEmailCode: profile update failed: $e');
      }

      final profile = await _loadOrCreateProfile(supaUser, displayNameHint: displayName);

      // Store PIN hash in public.users.
      try {
        await _waitForSessionReady(expectedUserId: supaUser.id);
        await SupabaseConfig.client.rpc('set_user_pin', params: {'pin_input': pin.trim()});
        // Immediately verify we can validate it (prevents silent misconfiguration).
        final ok = await _verifyPinViaRpcWithRetry(pin: pin, expectedUserId: supaUser.id);
        if (!ok) throw Exception('PIN could not be saved correctly. Please try again.');

        _pinEnabled = true;
        _lastEmail = normalized.toLowerCase();
        await _savePasswordForEmail(email: normalized, password: password);
        await _savePrefs();
      } on PostgrestException catch (e) {
        debugPrint('AuthService.verifySignupEmailCode set/verify pin failed: ${e.message} (code: ${e.code})');
        throw _friendlyPinRpcException(e);
      } catch (e) {
        debugPrint('AuthService.verifySignupEmailCode set/verify pin failed: $e');
        rethrow;
      }
      _currentUser = profile;
      notifyListeners();
      return profile;
    } on AuthException catch (e) {
      debugPrint('AuthService.verifySignupEmailCode auth error: ${e.message}');
      throw Exception(_friendlyAuthMessage(e));
    } catch (e) {
      debugPrint('AuthService.verifySignupEmailCode failed: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _validatePasswordOrThrow(String password) {
    final p = password.trim();
    if (p.length < 8) throw Exception('Password must be at least 8 characters.');

    // Basic strength rules (simple + deterministic; avoids extra packages).
    final hasLower = p.contains(RegExp(r'[a-z]'));
    final hasUpper = p.contains(RegExp(r'[A-Z]'));
    final hasDigit = p.contains(RegExp(r'\d'));
    if (!(hasLower && hasUpper && hasDigit)) {
      throw Exception('Password is too easy. Use upper, lower, and a number.');
    }

    // Very common passwords / patterns.
    final lower = p.toLowerCase();
    const banned = <String>{
      'password',
      'password1',
      'password123',
      '12345678',
      '87654321',
      'qwertyui',
      'qwerty123',
      'iloveyou',
      'admin123',
    };
    if (banned.contains(lower) || lower.contains('password')) {
      throw Exception('Password is too easy. Please choose a stronger password.');
    }
  }

  Future<AppUser> signIn({required String email, required String password}) async {
    _isLoading = true;
    notifyListeners();
    try {
      final normalized = email.trim();
      final res = await SupabaseConfig.auth
          .signInWithPassword(email: normalized, password: password)
          .timeout(_authTimeout);
      final supaUser = res.user;
      if (supaUser == null) throw Exception('Sign in failed. Please try again.');
      final profile = await _loadOrCreateProfile(supaUser, displayNameHint: null);
      _currentUser = profile;
      _lastEmail = (email.trim()).toLowerCase();
      await _savePasswordForEmail(email: email, password: password);
      await _savePrefs();
      notifyListeners();
      return profile;
    } on AuthException catch (e) {
      debugPrint('AuthService.signIn auth error: ${e.message}');
      throw Exception(_friendlyAuthMessage(e));
    } catch (e) {
      debugPrint('AuthService.signIn failed: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Signs in using email + PIN.
  ///
  /// Supabase Auth does not support PIN as a primary credential by default.
  /// To enable a smooth PIN login UX, we:
  /// 1) Sign in with a locally-saved password for this email (saved at signup and after password login)
  /// 2) Verify the PIN via `verify_user_pin` RPC
  ///
  /// If the password was never saved on this device (e.g., different device / cleared storage),
  /// we can't create a Supabase session and will ask the user to use password.
  Future<AppUser> signInWithPin({required String email, required String pin}) async {
    _validatePinOrThrow(pin);
    _isLoading = true;
    notifyListeners();
    try {
      final normalized = email.trim();
      if (normalized.isEmpty || !normalized.contains('@')) throw Exception('Please enter a valid email.');

      // Defensive: ensure app-state never considers us signed in during PIN login.
      // (Important when a previous session/profile was still in memory.)
      _currentUser = null;
      notifyListeners();

      final savedPassword = await _getSavedPasswordForEmail(normalized);
      if (savedPassword == null || savedPassword.trim().isEmpty) {
        throw Exception('PIN login is not available on this device yet. Please sign in once with password.');
      }

      // IMPORTANT: Supabase creates a session immediately after this call.
      // We suppress publishing that session until the PIN is verified.
      // Keep this flag TRUE until we either (a) publish the user on success
      // or (b) complete signOut on failure. Otherwise the auth listener may
      // briefly publish a signed-in user and the router can redirect.
      _holdProfileUntilPinVerified = true;
      final res = await SupabaseConfig.auth
          .signInWithPassword(email: normalized, password: savedPassword)
          .timeout(_authTimeout);
      final supaUser = res.user;
      if (supaUser == null) throw Exception('Sign in failed. Please try again.');

      try {
        await _waitForSessionReady(expectedUserId: supaUser.id);
        // Now that we have a session, validate the PIN against the backend.
        final ok = await _verifyPinViaRpcWithRetry(pin: pin, expectedUserId: supaUser.id);
        if (!ok) {
          // Common migration edge case: account was created before `pin_hash` existed,
          // so the PIN was never stored. If we can confirm pin_hash is missing,
          // attempt a safe self-repair (requires already having the user's password).
          final repaired = await _tryRepairMissingPinHash(supaUser: supaUser, pin: pin);
          if (!repaired) throw Exception('Incorrect PIN');
        }

        // PIN is correct: publish signed-in state.
        _holdProfileUntilPinVerified = false;
        final profile = await _loadOrCreateProfile(supaUser, displayNameHint: null);
        _currentUser = profile;
        _lastEmail = normalized.toLowerCase();
        _pinEnabled = true;
        await _savePrefs();
        notifyListeners();
        return profile;
      } on PostgrestException catch (e) {
        // Even RPC failures must not leave the user logged in.
        debugPrint('AuthService.signInWithPin verify_user_pin failed: ${e.message} (code: ${e.code})');
        await _revokeSessionAfterFailedPin();
        throw _friendlyPinRpcException(e);
      } catch (e) {
        // If the PIN is wrong (or verification fails), we MUST revoke the session
        // created by signInWithPassword, otherwise the router may treat the user
        // as authenticated.
        await _revokeSessionAfterFailedPin();
        rethrow;
      }
    } on AuthException catch (e) {
      debugPrint('AuthService.signInWithPin auth error: ${e.message}');
      throw Exception(_friendlyAuthMessage(e));
    } catch (e) {
      debugPrint('AuthService.signInWithPin failed: $e');
      if (e is Exception) rethrow;
      throw _friendlyPinRpcException(e);
    } finally {
      // NOTE: Do not forcibly reset `_holdProfileUntilPinVerified` here.
      // On a wrong PIN, we must keep holding until signOut completes; otherwise
      // the auth listener may publish a temporary authenticated user.
      _isLoading = false;
      notifyListeners();
    }
  }

  String _friendlyAuthMessage(AuthException e) {
    final msg = e.message.trim();
    final lower = msg.toLowerCase();

    // Common Supabase auth errors.
    if (lower.contains('invalid login credentials')) {
      return 'Incorrect email or password.';
    }

    if (lower.contains('email not confirmed')) {
      return 'Your email is not confirmed. If you want instant access after signup, disable “Confirm email” in Supabase Auth settings.';
    }

    if (lower.contains('user already registered') || lower.contains('already registered') || lower.contains('already exists')) {
      return 'Email is already exist';
    }

    // Supabase will throw this when email confirmations/magic links exceed provider limits.
    // Common variants: "over_email_send_rate_limit" or messages containing "email rate limit".
    if (lower.contains('over_email_send_rate_limit') || (lower.contains('email') && lower.contains('rate'))) {
      return 'Email sending is rate-limited right now. This usually happens because Supabase email confirmation is enabled. If you don\'t want any emails, disable “Confirm email” in Supabase → Authentication → Providers → Email.';
    }

    if (lower.contains('rate limit') || lower.contains('too many requests')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }

    // Supabase email provider / SMTP misconfiguration or blocked delivery.
    // When using signInWithOtp, Supabase may label the email as a "magic link" even if you intend OTP codes.
    if (lower.contains('error sending magic link email') || (lower.contains('unexpected_failure') && lower.contains('email'))) {
      return 'Supabase could not send the verification email. This is a backend email delivery issue (SMTP not configured / provider blocked). In Supabase go to Authentication → Providers → Email and configure SMTP, then try again.';
    }

    // Keep the original message as a fallback, but remove noisy prefixes.
    if (msg.isEmpty) return 'Authentication failed. Please try again.';
    return msg;
  }

  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();
    try {
      await SupabaseConfig.auth.signOut().timeout(_authTimeout);
      _currentUser = null;
      notifyListeners();
    } catch (e) {
      debugPrint('AuthService.signOut failed: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Re-fetches the user's profile from `public.users`.
  ///
  /// Useful after server-side changes (e.g., admin edits, RLS policy fixes).
  Future<void> refreshProfile() async {
    final supaUser = SupabaseConfig.auth.currentUser;
    if (supaUser == null) return;
    try {
      _currentUser = await _loadOrCreateProfile(supaUser, displayNameHint: null);
    } catch (e) {
      debugPrint('AuthService.refreshProfile failed: $e');
    } finally {
      notifyListeners();
    }
  }

  /// Verifies the current user's password.
  ///
  /// Supabase doesn't expose a pure "reauth" endpoint on the client; the most
  /// reliable check is a password sign-in attempt.
  Future<void> verifyCurrentPassword({required String password}) async {
    final email = _currentUser?.email.trim() ?? '';
    if (email.isEmpty) throw Exception('No signed-in user.');
    final p = password.trim();
    if (p.isEmpty) throw Exception('Please enter your password.');
    try {
      await SupabaseConfig.auth.signInWithPassword(email: email, password: p).timeout(_authTimeout);
      // If this password is correct, keep it cached to preserve PIN login.
      await _savePasswordForEmail(email: email, password: p);
    } on AuthException catch (e) {
      debugPrint('AuthService.verifyCurrentPassword auth error: ${e.message}');
      throw Exception(_friendlyAuthMessage(e));
    } catch (e) {
      debugPrint('AuthService.verifyCurrentPassword failed: $e');
      rethrow;
    }
  }

  /// Updates the Supabase Auth password after verifying the current password.
  Future<void> updatePassword({required String currentPassword, required String newPassword}) async {
    _isLoading = true;
    notifyListeners();
    try {
      await verifyCurrentPassword(password: currentPassword);
      _validatePasswordOrThrow(newPassword);
      await SupabaseConfig.auth.updateUser(UserAttributes(password: newPassword.trim())).timeout(_authTimeout);

      final email = _currentUser?.email.trim() ?? '';
      if (email.isNotEmpty) await _savePasswordForEmail(email: email, password: newPassword.trim());
    } on AuthException catch (e) {
      debugPrint('AuthService.updatePassword auth error: ${e.message}');
      throw Exception(_friendlyAuthMessage(e));
    } catch (e) {
      debugPrint('AuthService.updatePassword failed: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Updates the user's PIN hash after verifying the current password.
  Future<void> updatePin({required String currentPassword, required String newPin}) async {
    _isLoading = true;
    notifyListeners();
    try {
      await verifyCurrentPassword(password: currentPassword);
      await setPin(pin: newPin);
    } catch (e) {
      debugPrint('AuthService.updatePin failed: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<AppUser> _loadOrCreateProfile(User supaUser, {required String? displayNameHint}) async {
    final now = DateTime.now().toUtc();
    final email = (supaUser.email ?? '').trim();
    final metaDisplayName = (supaUser.userMetadata?['display_name'] ?? '').toString().trim();
    final displayName = (displayNameHint?.trim().isNotEmpty ?? false)
        ? displayNameHint!.trim()
        : (metaDisplayName.isNotEmpty ? metaDisplayName : 'Customer');

    // IMPORTANT:
    // Some schemas enforce NOT NULL constraints on trade fields (e.g. company_name).
    // In that case, doing a "minimal" upsert can fail with 23502 (not-null violation)
    // if the profile row doesn't exist yet.
    //
    // To avoid breaking profile loading (and to ensure we can still read existing
    // trade rows with company_name/phone_number), we:
    // 1) Try to SELECT the profile first
    // 2) Only attempt an upsert if the row is missing
    // 3) If upsert fails, we still return an auth-backed profile

    // 1) Prefer reading existing profile row.
    try {
      final existingRow = await SupabaseService.selectSingle('users', filters: {'id': supaUser.id});
      if (existingRow != null) {
        return AppUser(
          id: existingRow['id'].toString(),
          email: (existingRow['email'] ?? email).toString(),
          displayName: (existingRow['display_name'] ?? displayName).toString(),
          companyName: existingRow['company_name']?.toString(),
          phoneNumber: existingRow['phone_number']?.toString(),
          xeroAccountId: existingRow['xero_account_id']?.toString(),
          createdAt: DateTime.tryParse(existingRow['created_at']?.toString() ?? '') ?? now,
          updatedAt: DateTime.tryParse(existingRow['updated_at']?.toString() ?? '') ?? now,
        );
      }
    } on PostgrestException catch (e) {
      debugPrint('AuthService: profile select blocked by RLS: ${e.message} (code: ${e.code})');
      // Fall through to auth-backed profile.
    } catch (e) {
      debugPrint('AuthService: profile select failed: $e');
      // Fall through to upsert attempt.
    }

    // 2) Upsert profile row to ensure it exists.
    // NOTE: If your public.users table has RLS enabled but no INSERT/UPDATE policy,
    // Supabase will throw a PostgrestException (code 42501). We must NOT crash
    // the app for that; we can still treat the Supabase auth user as signed in.
    try {
      await SupabaseService.from('users').upsert({
        'id': supaUser.id,
        'email': email,
        'display_name': displayName,
        'updated_at': now.toIso8601String(),
      });
    } on PostgrestException catch (e) {
      debugPrint('AuthService: profile upsert blocked/failed: ${e.message} (code: ${e.code})');
      return AppUser(
        id: supaUser.id,
        email: email,
        displayName: displayName,
        companyName: null,
        phoneNumber: null,
        xeroAccountId: null,
        createdAt: now,
        updatedAt: now,
      );
    } catch (e) {
      debugPrint('AuthService: profile upsert failed: $e');
      return AppUser(
        id: supaUser.id,
        email: email,
        displayName: displayName,
        companyName: null,
        phoneNumber: null,
        xeroAccountId: null,
        createdAt: now,
        updatedAt: now,
      );
    }

    // 3) After upsert, fetch the row so we get trade fields.
    try {
      final row = await SupabaseService.selectSingle('users', filters: {'id': supaUser.id});
      if (row == null) {
        return AppUser(id: supaUser.id, email: email, displayName: displayName, companyName: null, phoneNumber: null, xeroAccountId: null, createdAt: now, updatedAt: now);
      }
      return AppUser(
        id: row['id'].toString(),
        email: (row['email'] ?? email).toString(),
        displayName: (row['display_name'] ?? displayName).toString(),
        companyName: row['company_name']?.toString(),
        phoneNumber: row['phone_number']?.toString(),
        xeroAccountId: row['xero_account_id']?.toString(),
        createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ?? now,
        updatedAt: DateTime.tryParse(row['updated_at']?.toString() ?? '') ?? now,
      );
    } on PostgrestException catch (e) {
      debugPrint('AuthService: profile select blocked by RLS: ${e.message} (code: ${e.code})');
      return AppUser(id: supaUser.id, email: email, displayName: displayName, companyName: null, phoneNumber: null, xeroAccountId: null, createdAt: now, updatedAt: now);
    } catch (e) {
      debugPrint('AuthService: profile select failed after upsert: $e');
      return AppUser(id: supaUser.id, email: email, displayName: displayName, companyName: null, phoneNumber: null, xeroAccountId: null, createdAt: now, updatedAt: now);
    }
  }

  @override
  void dispose() {
    if (_isInitialized) {
      try {
        _authSub.cancel();
      } catch (_) {}
    }
    super.dispose();
  }
}

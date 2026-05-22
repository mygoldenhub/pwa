import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:pwa/models/app_user.dart';
import 'package:pwa/nav.dart';
import 'package:pwa/supabase/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService extends ChangeNotifier {
  bool _isInitialized = false;
  bool _isLoading = false;
  AppUser? _currentUser;
  late final StreamSubscription<AuthState> _authSub;

  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;
  AppUser? get currentUser => _currentUser;
  bool get isSignedIn => _currentUser != null;

  Future<void> init() async {
    if (_isInitialized) return;
    _isLoading = true;
    notifyListeners();
    try {
      _authSub = SupabaseConfig.auth.onAuthStateChange.listen((event) async {
        final supaUser = event.session?.user;
        if (supaUser == null) {
          _currentUser = null;
          notifyListeners();
          return;
        }
        try {
          _currentUser = await _loadOrCreateProfile(supaUser, displayNameHint: null);
        } catch (e) {
          debugPrint('AuthService: failed to load profile: $e');
        }
        notifyListeners();
      });

      final existing = SupabaseConfig.auth.currentUser;
      if (existing != null) {
        _currentUser = await _loadOrCreateProfile(existing, displayNameHint: null);
      }
    } catch (e) {
      debugPrint('AuthService.init failed: $e');
    } finally {
      _isInitialized = true;
      _isLoading = false;
      notifyListeners();
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

      final res = await SupabaseConfig.auth.signUp(
        email: normalized,
        password: password,
        data: {
          // Stored in auth.users.user_metadata (and available as a hint for profile creation).
          'display_name': displayName.trim(),
        },
      );

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
          await SupabaseConfig.auth.signInWithPassword(email: normalized, password: password);
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
      await SupabaseConfig.auth.signInWithOtp(
        email: normalized,
        shouldCreateUser: true,
        data: {
          'display_name': displayName.trim(),
        },
      );
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
    required String password,
    required String code,
  }) async {
    _isLoading = true;
    notifyListeners();
    try {
      final normalized = email.trim();
      if (normalized.isEmpty || !normalized.contains('@')) throw Exception('Please enter a valid email.');
      final token = code.trim();
      if (token.length != 8 || token.contains(RegExp(r'\D'))) throw Exception('Please enter the 8-digit code.');
      _validatePasswordOrThrow(password);

      final res = await SupabaseConfig.auth.verifyOTP(
        type: OtpType.signup,
        email: normalized,
        token: token,
      );

      final supaUser = res.user ?? SupabaseConfig.auth.currentUser;
      if (supaUser == null) throw Exception('Verification succeeded, but no user was returned. Please try signing in.');

      // Attach password to the now-authenticated user.
      try {
        await SupabaseConfig.auth.updateUser(UserAttributes(
          password: password,
          data: {
            'display_name': displayName.trim(),
          },
        ));
      } on AuthException catch (e) {
        debugPrint('AuthService.verifySignupEmailCode updateUser error: ${e.message}');
        throw Exception(_friendlyAuthMessage(e));
      }

      final profile = await _loadOrCreateProfile(supaUser, displayNameHint: displayName);
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
      final res = await SupabaseConfig.auth.signInWithPassword(email: normalized, password: password);
      final supaUser = res.user;
      if (supaUser == null) throw Exception('Sign in failed. Please try again.');
      final profile = await _loadOrCreateProfile(supaUser, displayNameHint: null);
      _currentUser = profile;
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
      await SupabaseConfig.auth.signOut();
      _currentUser = null;
      notifyListeners();
    } catch (e) {
      debugPrint('AuthService.signOut failed: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<AppUser> _loadOrCreateProfile(User supaUser, {required String? displayNameHint}) async {
    final now = DateTime.now().toUtc();
    final email = (supaUser.email ?? '').trim();
    final displayName = (displayNameHint?.trim().isNotEmpty ?? false) ? displayNameHint!.trim() : 'Customer';

    // Upsert profile row to ensure it exists.
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
      debugPrint('AuthService: profile upsert blocked by RLS: ${e.message} (code: ${e.code})');
      return AppUser(
        id: supaUser.id,
        email: email,
        displayName: displayName,
        createdAt: now,
        updatedAt: now,
      );
    } catch (e) {
      debugPrint('AuthService: profile upsert failed: $e');
      return AppUser(
        id: supaUser.id,
        email: email,
        displayName: displayName,
        createdAt: now,
        updatedAt: now,
      );
    }

    try {
      final row = await SupabaseService.selectSingle('users', filters: {'id': supaUser.id});
      if (row == null) {
        return AppUser(id: supaUser.id, email: email, displayName: displayName, createdAt: now, updatedAt: now);
      }
      return AppUser(
        id: row['id'].toString(),
        email: (row['email'] ?? email).toString(),
        displayName: (row['display_name'] ?? displayName).toString(),
        createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ?? now,
        updatedAt: DateTime.tryParse(row['updated_at']?.toString() ?? '') ?? now,
      );
    } on PostgrestException catch (e) {
      debugPrint('AuthService: profile select blocked by RLS: ${e.message} (code: ${e.code})');
      return AppUser(id: supaUser.id, email: email, displayName: displayName, createdAt: now, updatedAt: now);
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

// Authentication Manager - Base interface for auth implementations
//
// This abstract class and mixins define the contract for authentication systems.
// Implement this with concrete classes for Firebase, Supabase, or local auth.
//
// Usage:
// 1. Create a concrete class extending AuthManager
// 2. Mix in the required authentication provider mixins
// 3. Implement all abstract methods with your auth provider logic

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pwa/supabase/supabase_config.dart';

// Core authentication operations that all auth implementations must provide
abstract class AuthManager {
  Future<void> signOut();
  Future<void> deleteUser(BuildContext context);
  Future<void> updateEmail({required String email, required BuildContext context});
  Future<void> resetPassword({required String email, required BuildContext context});
}

// Email/password authentication mixin
mixin EmailSignInManager on AuthManager {
  Future<User?> signInWithEmail(BuildContext context, String email, String password);

  Future<User?> createAccountWithEmail(BuildContext context, String email, String password);
}

/// Concrete Supabase implementation.
///
/// Note: This file isn't yet wired into the app's UI flow (the project currently
/// uses `AuthService`). It's provided so the repo has a consistent, reusable
/// auth abstraction as you expand.
class SupabaseAuthManager extends AuthManager with EmailSignInManager {
  @override
  Future<User?> createAccountWithEmail(
    BuildContext context,
    String email,
    String password,
  ) async {
    try {
      final res = await SupabaseConfig.auth.signUp(
        email: email.trim(),
        password: password,
      );
      return res.user;
    } catch (e) {
      debugPrint('SupabaseAuthManager.createAccountWithEmail failed: $e');
      rethrow;
    }
  }

  @override
  Future<User?> signInWithEmail(
    BuildContext context,
    String email,
    String password,
  ) async {
    try {
      final res = await SupabaseConfig.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      return res.user;
    } catch (e) {
      debugPrint('SupabaseAuthManager.signInWithEmail failed: $e');
      rethrow;
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await SupabaseConfig.auth.signOut();
    } catch (e) {
      debugPrint('SupabaseAuthManager.signOut failed: $e');
      rethrow;
    }
  }

  @override
  Future<void> deleteUser(BuildContext context) async {
    // Client-side delete isn't supported with anon key. This requires a secure
    // server-side function using the service role key.
    throw UnsupportedError('Deleting a Supabase user requires a server-side function.');
  }

  @override
  Future<void> updateEmail({required String email, required BuildContext context}) async {
    try {
      await SupabaseConfig.auth.updateUser(
        UserAttributes(email: email.trim()),
      );
    } catch (e) {
      debugPrint('SupabaseAuthManager.updateEmail failed: $e');
      rethrow;
    }
  }

  @override
  Future<void> resetPassword({required String email, required BuildContext context}) async {
    try {
      await SupabaseConfig.auth.resetPasswordForEmail(email.trim());
    } catch (e) {
      debugPrint('SupabaseAuthManager.resetPassword failed: $e');
      rethrow;
    }
  }
}

// Anonymous authentication for guest users
mixin AnonymousSignInManager on AuthManager {
  Future<User?> signInAnonymously(BuildContext context);
}

// Apple Sign-In authentication (iOS/web)
mixin AppleSignInManager on AuthManager {
  Future<User?> signInWithApple(BuildContext context);
}

// Google Sign-In authentication (all platforms)
mixin GoogleSignInManager on AuthManager {
  Future<User?> signInWithGoogle(BuildContext context);
}

// JWT token authentication for custom backends
mixin JwtSignInManager on AuthManager {
  Future<User?> signInWithJwtToken(
    BuildContext context,
    String jwtToken,
  );
}

// Phone number authentication with SMS verification
mixin PhoneSignInManager on AuthManager {
  Future beginPhoneAuth({
    required BuildContext context,
    required String phoneNumber,
    required void Function(BuildContext) onCodeSent,
  });

  Future verifySmsCode({
    required BuildContext context,
    required String smsCode,
  });
}

// Facebook Sign-In authentication
mixin FacebookSignInManager on AuthManager {
  Future<User?> signInWithFacebook(BuildContext context);
}

// Microsoft Sign-In authentication (Azure AD)
mixin MicrosoftSignInManager on AuthManager {
  Future<User?> signInWithMicrosoft(
    BuildContext context,
    List<String> scopes,
    String tenantId,
  );
}

// GitHub Sign-In authentication (OAuth)
mixin GithubSignInManager on AuthManager {
  Future<User?> signInWithGithub(BuildContext context);
}

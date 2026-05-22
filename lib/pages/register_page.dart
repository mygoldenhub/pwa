import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pwa/app_state.dart';
import 'package:pwa/components/auth_scaffold.dart';
import 'package:pwa/nav.dart';
import 'package:pwa/theme.dart';

class RegisterPage extends StatefulWidget {
  final AppState appState;
  const RegisterPage({super.key, required this.appState});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _displayNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;

  @override
  void dispose() {
    _displayNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final email = _emailController.text;
      final password = _passwordController.text;
      final displayName = _displayNameController.text;

      final normalizedEmail = email.trim();
      if (displayName.trim().isEmpty) throw Exception('Please enter your full name.');
      if (normalizedEmail.isEmpty || !normalizedEmail.contains('@')) throw Exception('Please enter a valid email.');

      // Password rules: >= 8 chars, and not too easy.
      if (password.trim().length < 8) throw Exception('Password must be at least 8 characters.');
      final hasLower = password.contains(RegExp(r'[a-z]'));
      final hasUpper = password.contains(RegExp(r'[A-Z]'));
      final hasDigit = password.contains(RegExp(r'\d'));
      if (!(hasLower && hasUpper && hasDigit)) throw Exception('Password is too easy. Use upper, lower, and a number.');
      final lower = password.trim().toLowerCase();
      if (lower.contains('password') || lower == '12345678' || lower == 'password123') {
        throw Exception('Password is too easy. Please choose a stronger password.');
      }

      // Pre-check (edge function) to prevent sending OTP for already-registered emails.
      // If this check fails (function not deployed / CORS / network), we STOP and show a message
      // because the expected UX is: only send code for new emails.
      final exists = await widget.appState.auth.emailExists(email: normalizedEmail);
      if (exists) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Email is already exist')));
        return;
      }

      await widget.appState.auth.requestSignupEmailCode(email: email, displayName: displayName);
      if (!mounted) return;
      context.go(
        AppRoutes.verifyEmail,
        extra: {
          'email': email,
          'password': password,
          'displayName': displayName,
        },
      );
    } catch (e) {
      debugPrint('Register failed: $e');
      if (!mounted) return;

      final msg = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isBusy = widget.appState.auth.isLoading || _submitting;

    return AuthScaffold(
      title: 'Create account',
      subtitle: 'Enter your details to get started.',
      icon: Icons.person_add_alt_1,
      showBack: true,
      onBack: () => context.go(AppRoutes.welcome),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _displayNameController,
            decoration: const InputDecoration(
              labelText: 'Full name',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email address',
              prefixIcon: Icon(Icons.alternate_email),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _passwordController,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'Password',
              helperText: 'Min 8 chars • Upper + lower + number',
              prefixIcon: const Icon(Icons.password),
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                color: cs.onSurfaceVariant,
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: isBusy ? null : _submit,
              icon: Icon(Icons.arrow_forward, color: cs.onPrimary),
              label: Text('Continue', style: TextStyle(color: cs.onPrimary)),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: isBusy ? null : () => context.go(AppRoutes.login),
            icon: Icon(Icons.login, color: cs.primary),
            label: Text('I already have an account', style: TextStyle(color: cs.primary)),
          ),
        ],
      ),
    );
  }
}

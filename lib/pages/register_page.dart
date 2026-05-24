import 'dart:async';

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
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _pinController = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;

  static const Duration _cooldown = Duration(seconds: 45);
  Timer? _timer;
  Duration _remaining = Duration.zero;
  bool _sendingCode = false;

  @override
  void dispose() {
    _displayNameController.dispose();
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _pinController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _remaining = _cooldown);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_remaining.inSeconds <= 1) {
        t.cancel();
        setState(() => _remaining = Duration.zero);
      } else {
        setState(() => _remaining -= const Duration(seconds: 1));
      }
    });
  }

  String _format(Duration d) {
    final s = d.inSeconds;
    final mm = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  Future<void> _sendCode() async {
    FocusScope.of(context).unfocus();
    if (_sendingCode || _remaining != Duration.zero) return;
    setState(() => _sendingCode = true);
    try {
      final displayName = _displayNameController.text;
      final email = _emailController.text;
      final normalizedEmail = email.trim();

      if (displayName.trim().isEmpty) throw Exception('Please enter your full name.');
      if (normalizedEmail.isEmpty || !normalizedEmail.contains('@')) throw Exception('Please enter a valid email.');

      final exists = await widget.appState.auth.emailExists(email: normalizedEmail);
      if (exists) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Email is already exist')));
        return;
      }

      await widget.appState.auth.requestSignupEmailCode(email: normalizedEmail, displayName: displayName);
      if (!mounted) return;
      _startCooldown();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('6-digit code sent to your email.')));
    } catch (e) {
      debugPrint('RegisterPage: send code failed: $e');
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _sendingCode = false);
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final email = _emailController.text;
      final password = _passwordController.text;
      final displayName = _displayNameController.text;
      final code = _codeController.text;
      final pin = _pinController.text;

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

      if (code.trim().length != 6 || code.trim().contains(RegExp(r'\D'))) throw Exception('Please enter the 6-digit code.');
      if (pin.trim().length != 4 || pin.trim().contains(RegExp(r'\D'))) throw Exception('PIN must be exactly 4 digits.');

      await widget.appState.auth.verifySignupEmailCode(
        email: normalizedEmail,
        displayName: displayName,
        password: password,
        code: code,
        pin: pin,
      );

      if (!mounted) return;
      context.go(AppRoutes.products);
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
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Verify code',
                    prefixIcon: Icon(Icons.shield_outlined),
                  ),
                  maxLength: 6,
                  buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
                  textInputAction: TextInputAction.next,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              SizedBox(
                height: 56,
                child: FilledButton(
                  onPressed: (isBusy || _sendingCode || _remaining != Duration.zero) ? null : _sendCode,
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                  ),
                  child: _sendingCode
                      ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary))
                      : Text(_remaining == Duration.zero ? 'Send code' : _format(_remaining)),
                ),
              ),
            ],
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
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _pinController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'PIN (4 digits)',
              prefixIcon: Icon(Icons.pin_outlined),
            ),
            maxLength: 4,
            buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
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

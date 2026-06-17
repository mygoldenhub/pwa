import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pwa/app_state.dart';
import 'package:pwa/components/auth_scaffold.dart';
import 'package:pwa/nav.dart';
import 'package:pwa/theme.dart';

class ResetPasswordPage extends StatefulWidget {
  final AppState appState;
  final String? initialEmail;
  const ResetPasswordPage({super.key, required this.appState, this.initialEmail});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final initial = (widget.initialEmail ?? '').trim();
    if (initial.isNotEmpty) _emailController.text = initial;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  bool get _isBusy => widget.appState.auth.isLoading;

  Future<void> _sendCode() async {
    FocusScope.of(context).unfocus();
    try {
      await widget.appState.auth.requestPasswordResetCode(email: _emailController.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verification code sent. Please check your email.')),
      );
    } catch (e) {
      debugPrint('ResetPasswordPage._sendCode failed: $e');
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _verifyCode() async {
    FocusScope.of(context).unfocus();
    try {
      final normalized = _emailController.text.trim().toLowerCase();
      await widget.appState.auth.verifyPasswordResetCode(
        email: _emailController.text,
        code: _codeController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code verified. Please set a new password.')));
      context.go(AppRoutes.newPassword, extra: {'email': normalized});
    } catch (e) {
      debugPrint('ResetPasswordPage._verifyCode failed: $e');
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AuthScaffold(
      title: 'Reset Password',
      subtitle: 'We’ll email you a 6-digit code. Verify it to set a new password.',
      icon: Icons.key_outlined,
      showLogo: false,
      showHeader: true,
      showBack: true,
      // During recovery, Supabase may temporarily create a signed-in session after OTP verification.
      // Our router guard redirects signed-in users away from /login unless flow=recovery is present.
      // So we include it here to ensure back always lands on Login (not Cart).
      onBack: () => context.go('${AppRoutes.login}?flow=recovery'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.alternate_email),
                  ),
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _sendCode(),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton(
                onPressed: _isBusy ? null : _sendCode,
                child: Text(_isBusy ? 'Sending…' : 'Send', style: TextStyle(color: cs.onPrimary)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
            decoration: const InputDecoration(
              labelText: 'Verify Code',
              prefixIcon: Icon(Icons.verified_outlined),
            ),
            onSubmitted: (_) => _verifyCode(),
          ),
          const SizedBox(height: AppSpacing.lg),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _isBusy ? null : _verifyCode,
              icon: Icon(Icons.lock_reset, color: cs.onPrimary),
              label: Text(_isBusy ? 'Please wait…' : 'Verify Code', style: TextStyle(color: cs.onPrimary)),
            ),
          ),
        ],
      ),
    );
  }
}

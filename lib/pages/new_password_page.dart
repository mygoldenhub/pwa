import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pwa/app_state.dart';
import 'package:pwa/components/auth_scaffold.dart';
import 'package:pwa/nav.dart';
import 'package:pwa/theme.dart';

class NewPasswordPage extends StatefulWidget {
  final AppState appState;
  final String email;
  const NewPasswordPage({super.key, required this.appState, required this.email});

  @override
  State<NewPasswordPage> createState() => _NewPasswordPageState();
}

class _NewPasswordPageState extends State<NewPasswordPage> {
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  bool get _isBusy => widget.appState.auth.isLoading;

  Future<void> _updatePassword() async {
    FocusScope.of(context).unfocus();

    final p1 = _newPasswordController.text.trim();
    final p2 = _confirmPasswordController.text.trim();
    if (p1.isEmpty || p2.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter your new password.')));
      return;
    }
    final policyError = widget.appState.auth.passwordPolicyError(p1);
    if (policyError != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(policyError)));
      return;
    }
    if (p1 != p2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Passwords do not match.')));
      return;
    }

    try {
      await widget.appState.auth.updateRecoveredPassword(newPassword: p1, emailHint: widget.email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password updated. Please log in.')));
      context.go(AppRoutes.login);
    } catch (e) {
      debugPrint('NewPasswordPage._updatePassword failed: $e');
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AuthScaffold(
      title: 'New Password',
      subtitle: 'Set a new password for your account.',
      icon: Icons.lock_outline,
      showLogo: false,
      showHeader: true,
      showBack: true,
      onBack: () {
        final email = widget.email.trim().toLowerCase();
        final q = <String, String>{'flow': 'recovery'};
        if (email.isNotEmpty) q['email'] = email;
        context.go(Uri(path: AppRoutes.resetPassword, queryParameters: q).toString());
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Must be at least 8 characters and include upper, lower, and a number.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _newPasswordController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'New Password', prefixIcon: Icon(Icons.password)),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _confirmPasswordController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Confirm Password', prefixIcon: Icon(Icons.password_outlined)),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _updatePassword(),
          ),
          const SizedBox(height: AppSpacing.lg),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _isBusy ? null : _updatePassword,
              icon: Icon(Icons.check_circle_outline, color: cs.onPrimary),
              label: Text(_isBusy ? 'Updating…' : 'Update Password', style: TextStyle(color: cs.onPrimary)),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pwa/app_state.dart';
import 'package:pwa/components/auth_scaffold.dart';
import 'package:pwa/nav.dart';
import 'package:pwa/theme.dart';

class LoginPage extends StatefulWidget {
  final AppState appState;
  const LoginPage({super.key, required this.appState});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    try {
      await widget.appState.auth.signIn(
        email: _emailController.text,
        password: _passwordController.text,
      );
      if (mounted) context.go(AppRoutes.products);
    } catch (e) {
      debugPrint('Login failed: $e');
      if (!mounted) return;

      final msg = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isBusy = widget.appState.auth.isLoading;

    return AuthScaffold(
      title: 'Login',
      subtitle: 'Enter your email and password to continue.',
      icon: Icons.lock_outline,
      showBack: true,
      onBack: () => context.go(AppRoutes.welcome),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
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
            autofillHints: const [AutofillHints.password],
            decoration: InputDecoration(
              labelText: 'Password',
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
              icon: Icon(Icons.login, color: cs.onPrimary),
              label: Text('Sign in', style: TextStyle(color: cs.onPrimary)),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: isBusy ? null : () => context.go(AppRoutes.register),
            icon: Icon(Icons.person_add_alt_1, color: cs.primary),
            label: Text('Create account', style: TextStyle(color: cs.primary)),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Having trouble signing in? Double-check your email and password.',
            style: Theme.of(context).textTheme.bodySmall?.withColor(cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

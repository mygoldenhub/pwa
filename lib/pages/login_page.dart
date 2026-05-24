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

enum _LoginMethod { pin, password }

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _pinController = TextEditingController();
  bool _obscure = true;
  _LoginMethod _method = _LoginMethod.pin;

  @override
  void initState() {
    super.initState();
    final last = widget.appState.auth.lastEmail;
    if (last != null && last.trim().isNotEmpty) _emailController.text = last.trim();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    try {
      if (_method == _LoginMethod.password) {
        final email = _emailController.text.trim();
        final password = _passwordController.text;
        if (email.isEmpty || !email.contains('@')) throw Exception('Please enter a valid email.');
        if (password.trim().isEmpty) throw Exception('Please enter your password.');
        await widget.appState.auth.signIn(email: email, password: password);
        if (mounted) context.go(AppRoutes.products);
        return;
      }

      // PIN mode: sign in via locally-saved password, then verify PIN.
      final email = _emailController.text.trim();
      final pin = _pinController.text;
      if (email.isEmpty || !email.contains('@')) throw Exception('Please enter a valid email.');
      await widget.appState.auth.signInWithPin(email: email, pin: pin);
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
      subtitle: 'Use password, or sign in quickly with your 4-digit PIN.',
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
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: AppSpacing.md),

          if (_method == _LoginMethod.password) ...[
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
          ] else ...[
            TextField(
              controller: _pinController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 4,
              buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
              decoration: const InputDecoration(
                labelText: 'PIN (4 digits)',
                prefixIcon: Icon(Icons.pin_outlined),
                helperText: 'If this is a new device, you may need to sign in once with password.',
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],

          const SizedBox(height: AppSpacing.lg),

          _LoginMethodPicker(
            method: _method,
            onChanged: isBusy
                ? null
                : (m) {
                    setState(() {
                      _method = m;
                      _passwordController.clear();
                      _pinController.clear();
                    });
                  },
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: isBusy ? null : _submit,
              icon: Icon(Icons.arrow_forward, color: cs.onPrimary),
              label: Text(isBusy ? 'Please wait…' : 'Continue', style: TextStyle(color: cs.onPrimary)),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
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

class _LoginMethodPicker extends StatelessWidget {
  final _LoginMethod method;
  final ValueChanged<_LoginMethod>? onChanged;

  const _LoginMethodPicker({required this.method, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ModeTile(
            selected: method == _LoginMethod.pin,
            icon: Icons.pin_outlined,
            title: 'PIN',
            subtitle: 'Quick unlock',
            onTap: onChanged == null ? null : () => onChanged!(_LoginMethod.pin),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _ModeTile(
            selected: method == _LoginMethod.password,
            icon: Icons.password,
            title: 'Password',
            subtitle: 'Full sign-in',
            onTap: onChanged == null ? null : () => onChanged!(_LoginMethod.password),
          ),
        ),
      ],
    );
  }
}

class _ModeTile extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _ModeTile({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final bg = selected ? cs.primaryContainer : cs.surfaceContainerHighest;
    final fg = selected ? cs.onPrimaryContainer : cs.onSurface;

    return Semantics(
      button: true,
      selected: selected,
      label: '$title mode',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: selected ? cs.primary : cs.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(icon, color: fg),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: textTheme.titleSmall?.copyWith(color: fg, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: textTheme.bodySmall?.copyWith(color: fg.withValues(alpha: 0.8))),
                  ],
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: selected
                    ? Icon(Icons.check_circle, key: const ValueKey('on'), color: cs.primary)
                    : Icon(Icons.circle_outlined, key: const ValueKey('off'), color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

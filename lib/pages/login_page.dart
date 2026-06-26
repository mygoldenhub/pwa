import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
        if (mounted) context.go(AppRoutes.cart);
        return;
      }

      // PIN mode: sign in via locally-saved password, then verify PIN.
      final email = _emailController.text.trim();
      final pin = _pinController.text;
      if (email.isEmpty || !email.contains('@')) throw Exception('Please enter a valid email.');
      await widget.appState.auth.signInWithPin(email: email, pin: pin);
      if (mounted) context.go(AppRoutes.cart);
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
      showLogo: false,
      showHeader: true,
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
              keyboardType: const TextInputType.numberWithOptions(signed: false, decimal: false),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
              obscureText: true,
              maxLength: 4,
              buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
              decoration: InputDecoration(
                labelText: 'PIN (4 digits)',
                prefixIcon: const Icon(Icons.pin_outlined),
                helper: Center(
                  child: Text(
                    'If this is a new device, you may need to sign in once with password.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).inputDecorationTheme.helperStyle ??
                        Theme.of(context).textTheme.bodySmall?.withColor(cs.onSurfaceVariant),
                  ),
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],

          const SizedBox(height: AppSpacing.lg),

          _OrDivider(),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              const Spacer(),
              TextButton(
                onPressed: isBusy ? null : () => context.go(AppRoutes.resetPassword),
                child: const Text('Forgot Password'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _LoginMethodIconPicker(
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
          const SizedBox(height: AppSpacing.sm),
          Text(
            _method == _LoginMethod.pin ? 'Quick unlock with your PIN' : 'Full sign-in with your password',
            style: Theme.of(context).textTheme.bodySmall?.withColor(cs.onSurfaceVariant),
            textAlign: TextAlign.center,
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

class _OrDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.labelMedium?.withColor(cs.onSurfaceVariant);

    return Row(
      children: [
        Expanded(child: Divider(height: 1, thickness: 1, color: cs.outlineVariant.withValues(alpha: 0.5))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text('or', style: textStyle),
        ),
        Expanded(child: Divider(height: 1, thickness: 1, color: cs.outlineVariant.withValues(alpha: 0.5))),
      ],
    );
  }
}

class _LoginMethodIconPicker extends StatelessWidget {
  final _LoginMethod method;
  final ValueChanged<_LoginMethod>? onChanged;

  const _LoginMethodIconPicker({required this.method, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _LoginMethodIconButton(
          selected: method == _LoginMethod.pin,
          enabled: onChanged != null,
          icon: Icons.pin_outlined,
          semanticsLabel: 'PIN login',
          onTap: onChanged == null ? null : () => onChanged!(_LoginMethod.pin),
        ),
        const SizedBox(width: AppSpacing.lg),
        _LoginMethodIconButton(
          selected: method == _LoginMethod.password,
          enabled: onChanged != null,
          icon: Icons.password,
          semanticsLabel: 'Password login',
          onTap: onChanged == null ? null : () => onChanged!(_LoginMethod.password),
        ),
      ],
    );
  }
}

class _LoginMethodIconButton extends StatelessWidget {
  final bool selected;
  final bool enabled;
  final IconData icon;
  final String semanticsLabel;
  final VoidCallback? onTap;

  const _LoginMethodIconButton({
    required this.selected,
    required this.enabled,
    required this.icon,
    required this.semanticsLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final bg = selected ? cs.primaryContainer : cs.surface;
    final borderColor = selected ? cs.primary : cs.outlineVariant.withValues(alpha: 0.45);
    final borderWidth = selected ? 2.0 : 1.0;
    final iconColor = selected ? cs.primary : cs.onSurfaceVariant;

    final shadowColor = cs.shadow.withValues(alpha: selected ? 0.12 : 0.08);
    final boxShadow = <BoxShadow>[
      BoxShadow(color: shadowColor, blurRadius: selected ? 16 : 12, offset: Offset(0, selected ? 10 : 8)),
    ];

    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: semanticsLabel,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: 54,
          width: 54,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor, width: borderWidth),
            boxShadow: enabled ? boxShadow : null,
          ),
          child: Stack(
            children: [
              Center(child: Icon(icon, color: iconColor, size: 22)),
              Positioned(
                right: 6,
                bottom: 6,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  opacity: selected ? 1 : 0,
                  child: Icon(Icons.check_circle, color: cs.primary, size: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}



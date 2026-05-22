import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pwa/app_state.dart';
import 'package:pwa/components/auth_scaffold.dart';
import 'package:pwa/nav.dart';
import 'package:pwa/theme.dart';

class VerifyEmailCodePage extends StatefulWidget {
  final AppState appState;
  final String email;
  final String displayName;
  final String password;

  const VerifyEmailCodePage({
    super.key,
    required this.appState,
    required this.email,
    required this.displayName,
    required this.password,
  });

  @override
  State<VerifyEmailCodePage> createState() => _VerifyEmailCodePageState();
}

class _VerifyEmailCodePageState extends State<VerifyEmailCodePage> {
  static const int _digits = 8;
  static const Duration _cooldown = Duration(seconds: 45);

  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;
  Timer? _timer;
  Duration _remaining = _cooldown;
  bool _submitting = false;
  bool _resending = false;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(_digits, (_) => TextEditingController());
    _focusNodes = List.generate(_digits, (_) => FocusNode());
    _startTimer();

    // Auto-focus first box after build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNodes.first.requestFocus();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final n in _focusNodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _startTimer() {
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

  String get _code => _controllers.map((c) => c.text.trim()).join();
  bool get _isComplete => _code.length == _digits && !_code.contains(RegExp(r'\D'));

  String _format(Duration d) {
    final s = d.inSeconds;
    final mm = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  void _clearAll() {
    for (final c in _controllers) {
      c.clear();
    }
    _focusNodes.first.requestFocus();
    setState(() {});
  }

  Future<void> _verify() async {
    FocusScope.of(context).unfocus();
    if (_submitting || !_isComplete) return;
    setState(() => _submitting = true);
    try {
      await widget.appState.auth.verifySignupEmailCode(
        email: widget.email,
        displayName: widget.displayName,
        password: widget.password,
        code: _code,
      );
      if (!mounted) return;
      context.go(AppRoutes.products);
    } catch (e) {
      debugPrint('VerifyEmailCodePage: verify failed: $e');
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      _clearAll();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _resend() async {
    if (_resending || _remaining != Duration.zero) return;
    setState(() => _resending = true);
    try {
      await widget.appState.auth.requestSignupEmailCode(
        email: widget.email,
        displayName: widget.displayName,
      );
      if (!mounted) return;
      _startTimer();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verification code resent.')),
      );
    } catch (e) {
      debugPrint('VerifyEmailCodePage: resend failed: $e');
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isBusy = widget.appState.auth.isLoading || _submitting;
    final email = widget.email.trim();

    return AuthScaffold(
      title: 'Enter $_digits-digit code',
      subtitle: email.isEmpty
          ? 'Check your email for the verification code.'
          : 'We sent a $_digits-digit code to\n$email',
      icon: Icons.shield_moon_outlined,
      showBack: true,
      onBack: () => context.go(AppRoutes.register),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: List.generate(_digits, (i) {
                return _OtpDigitBox(
                  controller: _controllers[i],
                  focusNode: _focusNodes[i],
                  enabled: !isBusy,
                  onChanged: (v) {
                    final text = v.trim();
                    if (text.isNotEmpty) {
                      if (i < _digits - 1) {
                        _focusNodes[i + 1].requestFocus();
                      } else {
                        FocusScope.of(context).unfocus();
                      }
                    }
                    setState(() {});
                  },
                  onBackspaceOnEmpty: () {
                    if (i > 0) {
                      _controllers[i - 1].text = '';
                      _focusNodes[i - 1].requestFocus();
                      setState(() {});
                    }
                  },
                );
              }),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: Text(
              _remaining == Duration.zero ? 'You can resend a code now.' : 'Resend code in ${_format(_remaining)}',
              style: Theme.of(context).textTheme.bodySmall?.withColor(cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: (!isBusy && _isComplete) ? _verify : null,
              child: Text(
                isBusy ? 'Verifying…' : 'Verify & Continue',
                style: TextStyle(color: cs.onPrimary),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.primary.withValues(alpha: 0.12),
                  ),
                  child: Icon(Icons.mark_email_read_outlined, color: cs.primary),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Didn't receive the code?",
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Check your spam folder or resend the code.',
                        style: Theme.of(context).textTheme.bodySmall?.withColor(cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                TextButton(
                  onPressed: (_remaining == Duration.zero && !_resending) ? _resend : null,
                  child: _resending
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                        )
                      : Text('Resend', style: TextStyle(color: cs.primary)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OtpDigitBox extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final VoidCallback onBackspaceOnEmpty;

  const _OtpDigitBox({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.onChanged,
    required this.onBackspaceOnEmpty,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      width: 48,
      height: 54,
      child: KeyboardListener(
        focusNode: FocusNode(skipTraversal: true),
        onKeyEvent: (event) {
          if (!enabled) return;
          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.backspace) {
            if (controller.text.isEmpty) onBackspaceOnEmpty();
          }
        },
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          enabled: enabled,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(1),
          ],
          decoration: InputDecoration(
            filled: true,
            fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.55),
            contentPadding: EdgeInsets.zero,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.55)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.55)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: BorderSide(color: cs.primary, width: 1.5),
            ),
          ),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pwa/app_state.dart';
import 'package:pwa/components/app_logo.dart';
import 'package:pwa/nav.dart';
import 'package:pwa/theme.dart';

class WelcomePage extends StatefulWidget {
  final AppState appState;
  const WelcomePage({super.key, required this.appState});

  // IMPORTANT: These must exist under your project's Assets panel.
  static const String _bgAssetMobile = 'assets/images/mobile-file.png';
  static const String _bgAssetWebDesktop = 'assets/images/web-file.png';
  static const double _mobileBreakpointWidth = 650;

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  final _displayNameController = TextEditingController();
  final _companyController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _pinController = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;

  static bool _isMobilePlatform() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return true;
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return false;
    }
  }

  static String _resolveBackgroundAsset(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isMobileLayout = width <= WelcomePage._mobileBreakpointWidth;
    if (_isMobilePlatform()) return WelcomePage._bgAssetMobile;
    if (kIsWeb && isMobileLayout) return WelcomePage._bgAssetMobile;
    return WelcomePage._bgAssetWebDesktop;
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _companyController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await widget.appState.auth.registerTradeAccount(
        displayName: _displayNameController.text,
        companyName: _companyController.text,
        email: _emailController.text,
        phoneNumber: _phoneController.text,
        password: _passwordController.text,
        pin: _pinController.text,
      );
      if (!mounted) return;
      context.go(AppRoutes.products);
    } catch (e) {
      debugPrint('WelcomePage register failed: $e');
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isBusy = widget.appState.auth.isLoading || _submitting;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              _resolveBackgroundAsset(context),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                debugPrint('WelcomePage background asset missing: $error');
                return DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        cs.primaryContainer.withValues(alpha: 0.60),
                        cs.surfaceContainerHighest,
                        Theme.of(context).scaffoldBackgroundColor,
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withValues(alpha: 0.60), Colors.black.withValues(alpha: 0.12)],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xl),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: constraints.maxHeight),
                          child: IntrinsicHeight(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(height: AppSpacing.sm),
                                const _WelcomeBrandHeader(),
                                const SizedBox(height: AppSpacing.lg),
                                TweenAnimationBuilder<double>(
                                  tween: Tween(begin: 0.0, end: 1.0),
                                  duration: const Duration(milliseconds: 520),
                                  curve: Curves.easeOutCubic,
                                  builder: (context, t, child) => Transform.translate(
                                    offset: Offset(0, 16 * (1 - t)),
                                    child: Opacity(opacity: t, child: child),
                                  ),
                                  child: _WelcomeRegisterCard(
                                    displayNameController: _displayNameController,
                                    companyController: _companyController,
                                    emailController: _emailController,
                                    phoneController: _phoneController,
                                    passwordController: _passwordController,
                                    pinController: _pinController,
                                    obscure: _obscure,
                                    submitting: isBusy,
                                    onToggleObscure: () => setState(() => _obscure = !_obscure),
                                    onContinue: isBusy ? null : _submit,
                                    onExistingAccount: isBusy ? null : () => context.go(AppRoutes.login),
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.lg),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WelcomeBrandHeader extends StatelessWidget {
  const _WelcomeBrandHeader();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 480),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Transform.translate(
        offset: Offset(0, -10 * (1 - t)),
        child: Opacity(opacity: t, child: child),
      ),
      child: Column(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            ),
            child: const Padding(
              padding: EdgeInsets.all(10),
              child: AppLogo(size: 170, borderRadius: BorderRadius.all(Radius.circular(20))),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Scan & Go',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(color: Colors.white).semiBold,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'STAFFLESS STORE',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.80),
                  letterSpacing: 1.2,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xs),
          Container(
            width: 84,
            height: 2,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }
}

class _WelcomeRegisterCard extends StatelessWidget {
  final TextEditingController displayNameController;
  final TextEditingController companyController;
  final TextEditingController emailController;
  final TextEditingController phoneController;
  final TextEditingController passwordController;
  final TextEditingController pinController;
  final bool obscure;
  final bool submitting;
  final VoidCallback onToggleObscure;
  final VoidCallback? onContinue;
  final VoidCallback? onExistingAccount;

  const _WelcomeRegisterCard({
    required this.displayNameController,
    required this.companyController,
    required this.emailController,
    required this.phoneController,
    required this.passwordController,
    required this.pinController,
    required this.obscure,
    required this.submitting,
    required this.onToggleObscure,
    required this.onContinue,
    required this.onExistingAccount,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.xl),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, AppSpacing.lg),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Create account', style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white).semiBold, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Enter your details. We’ll create your customer in Xero and save your trade account.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.white.withValues(alpha: 0.84), height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              _GlassTextField(controller: displayNameController, labelText: 'Full name', icon: Icons.badge_outlined, keyboardType: TextInputType.name, enabled: !submitting),
              const SizedBox(height: AppSpacing.md),
              _GlassTextField(controller: companyController, labelText: 'Company', icon: Icons.apartment_outlined, keyboardType: TextInputType.text, enabled: !submitting),
              const SizedBox(height: AppSpacing.md),
              _GlassTextField(controller: emailController, labelText: 'Email', icon: Icons.alternate_email, keyboardType: TextInputType.emailAddress, enabled: !submitting),
              const SizedBox(height: AppSpacing.md),
              _GlassTextField(controller: phoneController, labelText: 'Mobile number', icon: Icons.phone_outlined, keyboardType: TextInputType.phone, enabled: !submitting),
              const SizedBox(height: AppSpacing.md),
              _GlassTextField(controller: pinController, labelText: 'PIN (4 digits)', icon: Icons.pin_outlined, keyboardType: TextInputType.number, enabled: !submitting, maxLength: 4),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: passwordController,
                enabled: !submitting,
                obscureText: obscure,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Password',
                  helperText: 'Min 8 chars • Upper + lower + number',
                  prefixIcon: const Icon(Icons.password),
                  suffixIcon: IconButton(
                    onPressed: submitting ? null : onToggleObscure,
                    icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ).applyDefaults(Theme.of(context).inputDecorationTheme).copyWith(
                      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.90)),
                      helperStyle: TextStyle(color: Colors.white.withValues(alpha: 0.75)),
                      prefixIconColor: Colors.white.withValues(alpha: 0.85),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.10),
                    ),
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                height: 54,
                child: FilledButton.icon(
                  onPressed: onContinue,
                  icon: submitting
                      ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary))
                      : Icon(Icons.arrow_forward, color: cs.onPrimary),
                  label: Text(submitting ? 'Creating…' : 'Continue', style: TextStyle(color: cs.onPrimary)),
                  style: FilledButton.styleFrom(backgroundColor: cs.primary, foregroundColor: cs.onPrimary, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16)),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              const _OrDivider(),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: onExistingAccount,
                icon: const Icon(Icons.person, color: Colors.white),
                label: const Text('Existing trade account', style: TextStyle(color: Colors.white)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassTextField extends StatelessWidget {
  final TextEditingController controller;
  final String labelText;
  final IconData icon;
  final TextInputType keyboardType;
  final bool enabled;
  final int? maxLength;

  const _GlassTextField({
    required this.controller,
    required this.labelText,
    required this.icon,
    required this.keyboardType,
    required this.enabled,
    this.maxLength,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      maxLength: maxLength,
      buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: labelText,
        prefixIcon: Icon(icon),
      ).applyDefaults(Theme.of(context).inputDecorationTheme).copyWith(
            labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.90)),
            prefixIconColor: Colors.white.withValues(alpha: 0.85),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.10),
          ),
      textInputAction: TextInputAction.next,
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.white.withValues(alpha: 0.85));
    return Row(
      children: [
        Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.18), height: 1)),
        Padding(padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md), child: Text('OR', style: style)),
        Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.18), height: 1)),
      ],
    );
  }
}

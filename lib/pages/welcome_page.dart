import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:ui' show ImageFilter;
import 'package:go_router/go_router.dart';
import 'package:pwa/components/app_logo.dart';
import 'package:pwa/nav.dart';
import 'package:pwa/theme.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  // IMPORTANT: These must exist under your project's Assets panel.
  // Upload the files to: assets/images/
  //
  // - Mobile: used for Android/iOS (and for mobile browsers on Flutter web)
  // - Web (desktop): used for desktop browsers on Flutter web
  static const String _bgAssetMobile = 'assets/images/mobile-file.png';
  static const String _bgAssetWebDesktop = 'assets/images/web-file.png';

  // When running on the web, `defaultTargetPlatform` is not always enough
  // (some mobile browsers can report desktop-ish platforms, and users can
  // resize the window). So we also use a simple responsive breakpoint.
  static const double _mobileBreakpointWidth = 650;

  static bool _isMobilePlatform() {
    // When running on Web, defaultTargetPlatform reflects the browser platform
    // (Android/iOS for mobile browsers, macOS/windows/linux for desktop).
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
    final isMobileLayout = width <= _mobileBreakpointWidth;
    // Priority:
    // 1) Native mobile platforms should always use the mobile image.
    // 2) On web, use the mobile image for mobile-sized viewports (phones).
    // 3) Otherwise, use the desktop image.
    if (_isMobilePlatform()) return _bgAssetMobile;
    if (kIsWeb && isMobileLayout) return _bgAssetMobile;
    return _bgAssetWebDesktop;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              _resolveBackgroundAsset(context),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                debugPrint('WelcomePage background asset missing. Error: $error');
                // Keeps the screen usable even if the asset isn't added yet.
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
                constraints: const BoxConstraints(maxWidth: 520),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xl),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Keep the "modal" centered, but allow scrolling on smaller screens.
                      return SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: constraints.maxHeight),
                          child: IntrinsicHeight(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(height: AppSpacing.sm),
                                const _WelcomeBrandHeader(),
                                const SizedBox(height: AppSpacing.xl),
                                TweenAnimationBuilder<double>(
                                  tween: Tween(begin: 0.0, end: 1.0),
                                  duration: const Duration(milliseconds: 520),
                                  curve: Curves.easeOutCubic,
                                  builder: (context, t, child) {
                                    return Transform.translate(
                                      offset: Offset(0, 16 * (1 - t)),
                                      child: Opacity(opacity: t, child: child),
                                    );
                                  },
                                  child: _WelcomeCard(
                                    onExistingAccount: () => context.go(AppRoutes.login),
                                    onCreateAccount: () => context.go(AppRoutes.register),
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
      builder: (context, t, child) {
        return Transform.translate(
          offset: Offset(0, -10 * (1 - t)),
          child: Opacity(opacity: t, child: child),
        );
      },
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
              child: AppLogo(size: 130, borderRadius: BorderRadius.all(Radius.circular(20))),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Scan & Go',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              height: 1.05,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'STAFFLESS STORE',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.80),
              letterSpacing: 1.6,
              fontWeight: FontWeight.w700,
            ),
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

class _WelcomeCard extends StatelessWidget {
  final VoidCallback onExistingAccount;
  final VoidCallback onCreateAccount;

  const _WelcomeCard({required this.onExistingAccount, required this.onCreateAccount});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Frosted/transparent white modal.
    // Uses BackdropFilter for blur + semi-transparent surface tint.
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.xl),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, AppSpacing.lg),
          decoration: BoxDecoration(
            // A white-ish surface with opacity so the background subtly shows through.
            color: cs.surface.withValues(alpha: 0.86),
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Welcome!', style: Theme.of(context).textTheme.headlineMedium?.semiBold, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Access your trade account\nor create a new one to start shopping.',
                style: Theme.of(context).textTheme.bodyLarge?.withColor(cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: onExistingAccount,
                icon: Icon(Icons.person, color: cs.onPrimary),
                label: Text('Existing Trade Account', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: cs.onPrimary)),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16)),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Sign in to access your account and shop.',
                style: Theme.of(context).textTheme.bodyMedium?.withColor(cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              const _OrDivider(),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: onCreateAccount,
                icon: Icon(Icons.person_add_alt_1, color: AppSemanticColors.success),
                label: Text(
                  'New Customer / Create Account',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AppSemanticColors.success),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppSemanticColors.success.withValues(alpha: 0.55)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Create a new account to get started.',
                style: Theme.of(context).textTheme.bodyMedium?.withColor(cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              Center(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Need help? ', style: Theme.of(context).textTheme.bodyMedium?.withColor(cs.onSurfaceVariant)),
                    TextButton(
                      onPressed: () {},
                      child: Text('Contact support', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.primary)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.labelMedium?.withColor(cs.onSurfaceVariant);

    return Row(
      children: [
        Expanded(child: Divider(color: cs.outline.withValues(alpha: 0.18), height: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text('OR', style: style),
        ),
        Expanded(child: Divider(color: cs.outline.withValues(alpha: 0.18), height: 1)),
      ],
    );
  }
}

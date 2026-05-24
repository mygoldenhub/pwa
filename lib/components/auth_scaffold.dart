import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pwa/components/app_logo.dart';
import 'package:pwa/nav.dart';
import 'package:pwa/theme.dart';

/// A modern, reusable scaffold for auth/onboarding screens.
///
/// Provides:
/// - Light, layered background
/// - Optional back button
/// - Header icon + title/subtitle
/// - Centered, mobile-friendly max width
class AuthScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget child;
  final bool showLogo;
  final bool showBack;
  final VoidCallback? onBack;
  final EdgeInsetsGeometry? padding;

  const AuthScaffold({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.subtitle,
    this.showLogo = true,
    this.showBack = false,
    this.onBack,
    this.padding,
  });

  void _handleBack(BuildContext context) {
    if (onBack != null) {
      onBack!.call();
      return;
    }

    // Default auth back behavior:
    // - If there is a page to pop, pop it.
    // - Otherwise, go to the Welcome (Entry Gate) screen.
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go(AppRoutes.welcome);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return PopScope(
      canPop: !(showBack && onBack != null),
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (!showBack) return;
        if (onBack == null) return;
        _handleBack(context);
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        cs.primaryContainer.withValues(alpha: 0.55),
                        Theme.of(context).scaffoldBackgroundColor,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 10,
                left: 12,
                child: GestureDetector(
                  onTap: () => context.go(AppRoutes.welcome),
                  child: const AppCornerBrand(logoSize: 51),
                ),
              ),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: SingleChildScrollView(
                    padding: padding ?? AppSpacing.paddingLg,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (showBack)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: IconButton(
                              tooltip: 'Back',
                              onPressed: () => _handleBack(context),
                              icon: Icon(Icons.arrow_back, color: cs.onSurface),
                            ),
                          ),
                        Container(
                          padding: AppSpacing.paddingLg,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(AppRadius.xl),
                            color: cs.surface,
                            border: Border.all(
                                color: cs.outline.withValues(alpha: 0.12)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.xl),
                                  color: cs.surfaceContainerHighest,
                                  border: Border.all(
                                    color: cs.outline.withValues(alpha: 0.14),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Icon(icon, color: cs.primary),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.semiBold,
                                    ),
                                    if (subtitle != null) ...[
                                      const SizedBox(height: AppSpacing.xs),
                                      Text(
                                        subtitle!,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.withColor(cs.onSurfaceVariant),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          child: Container(
                            key: ValueKey(title),
                            padding: AppSpacing.paddingLg,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(AppRadius.xl),
                              color: cs.surface,
                              border: Border.all(
                                  color: cs.outline.withValues(alpha: 0.12)),
                            ),
                            child: child,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  final Color color;
  final double size;
  const _Blob({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(size),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:pwa/theme.dart';

/// Displays the app logo from assets with a safe fallback when missing.
class AppLogo extends StatelessWidget {
  final double size;
  final String assetPath;
  final BorderRadiusGeometry borderRadius;
  final BoxFit fit;
  final bool withBadge;
  final EdgeInsetsGeometry badgePadding;
  final double badgeBorderWidth;

  const AppLogo({
    super.key,
    required this.size,
    this.assetPath = AppAssets.logo,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.fit = BoxFit.cover,
    this.withBadge = false,
    this.badgePadding = const EdgeInsets.all(4),
    this.badgeBorderWidth = 1,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget logo = ClipRRect(
      borderRadius: borderRadius,
      child: Image.asset(
        assetPath,
        width: size,
        height: size,
        fit: fit,
        errorBuilder: (context, error, stackTrace) {
          debugPrint('AppLogo asset missing ($assetPath). Error: $error');
          return Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: borderRadius,
            ),
            child: Icon(Icons.storefront, color: cs.onPrimaryContainer),
          );
        },
      ),
    );

    if (!withBadge) return logo;

    // Make small logos visible on top of busy app bars / gradients by giving
    // them a subtle surface badge and border.
    return Container(
      padding: badgePadding,
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.92),
        borderRadius: borderRadius,
        border: Border.all(color: cs.outline.withValues(alpha: 0.22), width: badgeBorderWidth),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: logo,
    );
  }
}

/// Compact brand mark used in top-left corners (non-dashboard).
///
/// Shows the logo + the brand text (“Scan & Go”) inside a modern badge so it
/// stays readable on busy app bars / gradients.
class AppCornerBrand extends StatelessWidget {
  final double logoSize;
  final String title;
  final String assetPath;
  final BorderRadiusGeometry borderRadius;
  final EdgeInsetsGeometry padding;
  final double borderWidth;

  const AppCornerBrand({
    super.key,
    // Scaled up to improve readability in app bars.
    this.logoSize = 51,
    this.title = 'Scan & Go',
    this.assetPath = AppAssets.cornerLogo,
    this.borderRadius = const BorderRadius.all(Radius.circular(21)),
    this.padding = const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
    this.borderWidth = 1,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.titleSmall?.semiBold;

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.92),
        borderRadius: borderRadius,
        border: Border.all(color: cs.outline.withValues(alpha: 0.22), width: borderWidth),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppLogo(
            size: logoSize,
            assetPath: assetPath,
            borderRadius: BorderRadius.circular(15),
            fit: BoxFit.contain,
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textStyle?.copyWith(color: cs.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pwa/theme.dart';

/// Displays the app logo from assets with a safe fallback when missing.
class AppLogo extends StatelessWidget {
  final double size;
  final String assetPath;
  final BorderRadiusGeometry borderRadius;
  final BoxFit fit;

  const AppLogo({
    super.key,
    required this.size,
    this.assetPath = AppAssets.logo,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ClipRRect(
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
  }
}

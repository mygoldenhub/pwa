import 'package:flutter/material.dart';
import 'package:pwa/components/app_logo.dart';
import 'package:pwa/theme.dart';

enum AppHeaderTone { light, dark }

/// A modern, high-impact header used across the authenticated app.
///
/// - Top-left: a single “tab” that combines the diamond logo + current page label
/// - No ripple/splash effects (gesture based)
/// - Subtle animation when switching tabs
class AppImpactHeader extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final Widget? leading;
  final List<Widget>? actions;
  final AppHeaderTone tone;

  const AppImpactHeader({
    super.key,
    this.title,
    this.leading,
    this.actions,
    this.tone = AppHeaderTone.light,
  });

  @override
  Size get preferredSize => const Size.fromHeight(74);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final isDark = tone == AppHeaderTone.dark;
    final bg = isDark ? Colors.black : cs.surface;
    final border = isDark ? Colors.white.withValues(alpha: 0.12) : cs.outline.withValues(alpha: 0.10);
    final label = (title ?? '').trim();

    // App-wide change: remove the top-left logo from all pages.
    final effectiveLeading = leading;

    return Material(
      color: bg,
      child: SafeArea(
        bottom: false,
        child: Container(
          height: preferredSize.height,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: border, width: 1))),
          child: Row(
            children: [
              if (effectiveLeading != null) ...[effectiveLeading, const SizedBox(width: 10)],
              _HeaderTitlePill(label: label.isEmpty ? ' ' : label, tone: tone),
              const Spacer(),
              if (actions != null) ...[
                const SizedBox(width: 8),
                ...actions!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderTitlePill extends StatelessWidget {
  final AppHeaderTone tone;
  final String label;

  const _HeaderTitlePill({required this.label, required this.tone});

  bool _shouldUseSmallLogo(String label) {
    final l = label.trim().toLowerCase();
    return l == 'cart' || l == 'invoice' || l == 'invoices' || l == 'account' || l == 'product' || l == 'products';
  }

  IconData _iconForLabel(String label) {
    final l = label.trim().toLowerCase();
    if (l == 'cart') return Icons.shopping_cart_outlined;
    if (l == 'invoice' || l == 'invoices') return Icons.receipt_long_outlined;
    if (l == 'account') return Icons.person_outline;
    if (l.contains('scan')) return Icons.qr_code_scanner;
    if (l.contains('edit')) return Icons.edit_outlined;
    if (l.contains('new')) return Icons.add_circle_outline;
    return Icons.circle_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = tone == AppHeaderTone.dark;

    final pillBg = isDark ? Colors.white.withValues(alpha: 0.08) : cs.surface;
    final border = isDark ? Colors.white.withValues(alpha: 0.16) : cs.outline.withValues(alpha: 0.14);
    final fg = isDark ? Colors.white : cs.onSurface;

    final useSmallLogo = _shouldUseSmallLogo(label);
    final icon = _iconForLabel(label);
    final iconBg = isDark ? Colors.white.withValues(alpha: 0.10) : cs.primaryContainer;
    final iconFg = isDark ? Colors.white : cs.onPrimaryContainer;

    const pillIconOuter = 42.0;
    const pillIconPadding = 4.0;
    const pillLogoSize = 32.0;

    return Semantics(
      label: label,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: pillBg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: pillIconOuter,
              height: pillIconOuter,
              decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(999)),
              child: useSmallLogo
                  ? const Padding(
                      padding: EdgeInsets.all(pillIconPadding),
                      child: AppLogo(
                        size: pillLogoSize,
                        assetPath: AppAssets.smallLogo,
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                        fit: BoxFit.contain,
                      ),
                    )
                  : Icon(icon, color: iconFg, size: 20),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.semiBold.copyWith(color: fg, letterSpacing: 0.2),
            ),
          ],
        ),
      ),
    );
  }
}

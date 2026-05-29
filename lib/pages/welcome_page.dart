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
  static const String _bgAssetMobile = 'assets/images/mobile-file.jpg';
  static const String _bgAssetWebDesktop = 'assets/images/web-file.jpg';
  static const double _mobileBreakpointWidth = 650;

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
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
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isBusy = widget.appState.auth.isLoading;
    final size = MediaQuery.sizeOf(context);
    final isCompactHeight = size.height < 740;

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
                  // Stronger overlay to keep text readable over bright photos.
                  colors: [
                    Colors.black.withValues(alpha: 0.84),
                    Colors.black.withValues(alpha: 0.62),
                    Colors.black.withValues(alpha: 0.36),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Mobile: keep everything visible without requiring scroll.
                // We adapt by tightening spacing and (when needed) scaling the whole content down.
                final topPad = isCompactHeight ? AppSpacing.md : AppSpacing.lg;
                final bottomPad = isCompactHeight ? AppSpacing.lg : AppSpacing.xl;
                final availableHeight = (constraints.maxHeight - topPad - bottomPad).clamp(1.0, 99999.0);

                // Rough "ideal" height of this screen at 1.0 scale.
                // If the viewport is shorter, we scale down slightly rather than forcing scroll.
                const idealHeight = 700.0;
                final scale = (availableHeight / idealHeight).clamp(0.84, 1.0);

                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(AppSpacing.lg, topPad, AppSpacing.lg, bottomPad),
                      child: Transform.scale(
                        scale: scale,
                        alignment: Alignment.topCenter,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(height: isCompactHeight ? 0 : AppSpacing.sm),
                            _WelcomeBrandHeader(compact: isCompactHeight),
                            SizedBox(height: isCompactHeight ? AppSpacing.md : AppSpacing.lg),
                            TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0.0, end: 1.0),
                              duration: const Duration(milliseconds: 520),
                              curve: Curves.easeOutCubic,
                              builder: (context, t, child) => Transform.translate(
                                offset: Offset(0, 14 * (1 - t)),
                                child: Opacity(opacity: t, child: child),
                              ),
                              child: _EntryGateCard(
                                busy: isBusy,
                                onExisting: isBusy ? null : () => context.go(AppRoutes.login),
                                onNew: isBusy ? null : () => context.go(AppRoutes.register),
                                compact: isCompactHeight,
                              ),
                            ),
                            SizedBox(height: isCompactHeight ? AppSpacing.sm : AppSpacing.md),
                            _WelcomeDisclaimer(compact: isCompactHeight),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _WelcomeBrandHeader extends StatelessWidget {
  final bool compact;
  const _WelcomeBrandHeader({required this.compact});

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
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: AppLogo(
                size: compact ? 136 : 170,
                borderRadius: const BorderRadius.all(Radius.circular(20)),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Scan & Go',
            style: (compact
                    ? Theme.of(context).textTheme.headlineLarge
                    : Theme.of(context).textTheme.displaySmall)
                ?.copyWith(
              color: Colors.white,
              shadows: [
                Shadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 18,
                    offset: const Offset(0, 6)),
              ],
            ).semiBold,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Trade portal • Staffless checkout',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.96),
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _EntryGateCard extends StatelessWidget {
  final bool busy;
  final VoidCallback? onExisting;
  final VoidCallback? onNew;
  final bool compact;

  const _EntryGateCard(
      {required this.busy,
      required this.onExisting,
      required this.onNew,
      required this.compact});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        compact ? AppSpacing.md : AppSpacing.lg,
        AppSpacing.lg,
        compact ? AppSpacing.md : AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        // Higher opacity for readability over photos.
        color: Colors.black.withValues(alpha: 0.34),
        border: Border.all(color: Colors.white.withValues(alpha: 0.26)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Choose how you want to enter',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(color: Colors.white)
                .semiBold,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Log in to scan materials and check out without staff assistance.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.white.withValues(alpha: 0.92)),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
          _GateOptionTile(
            title: 'Existing trade account',
            subtitle: 'Sign in with email + PIN (or password).',
            icon: Icons.verified_user_outlined,
            trailingIcon: Icons.arrow_forward,
            onTap: onExisting,
          ),
          const SizedBox(height: AppSpacing.sm),
          _GateOptionTile(
            title: 'New customer / create account',
            subtitle:
                'Register in under a minute — we’ll create your Xero contact.',
            icon: Icons.person_add_alt_1,
            trailingIcon: Icons.arrow_forward,
            onTap: onNew,
          ),
          if (busy) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white)),
                const SizedBox(width: AppSpacing.sm),
                Text('Please wait…',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.86))),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _WelcomeDisclaimer extends StatelessWidget {
  final bool compact;
  const _WelcomeDisclaimer({required this.compact});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: compact ? AppSpacing.xs : AppSpacing.sm),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        color: Colors.black.withValues(alpha: 0.22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Text(
        'By continuing, you agree to be billed via your trade account and receive invoices by email.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.88), height: 1.35),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _GateOptionTile extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final IconData trailingIcon;
  final VoidCallback? onTap;

  const _GateOptionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.trailingIcon,
    required this.onTap,
  });

  @override
  State<_GateOptionTile> createState() => _GateOptionTileState();
}

class _GateOptionTileState extends State<_GateOptionTile> {
  bool _hovered = false;
  bool _pressed = false;

  static const int _labelMaxLines = 3;

  double _labelHeight(BuildContext context) {
    final style = Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          height: 1.18,
        );
    final fontSize = style?.fontSize ?? 16;
    final heightFactor = style?.height ?? 1.18;
    // Reserve enough vertical space for the *largest* label (title/subtitle)
    // so the tile size stays stable when switching on hover.
    return fontSize * heightFactor * _labelMaxLines;
  }

  Widget _buildAnimatedLabel(BuildContext context, {required bool active}) {
    final style = Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          height: 1.18,
        );

    return SizedBox(
      height: _labelHeight(context),
      child: Align(
        alignment: Alignment.centerLeft,
        // Web-friendly: keep both labels in the tree and animate opacity/slide.
        // This avoids AnimatedSwitcher doing widget replacement/layout work that
        // can feel janky on hover in browsers.
        child: RepaintBoundary(
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              _HoverSwapText(
                visible: !active,
                text: widget.title,
                style: style,
                maxLines: _labelMaxLines,
                // Title slides up slightly when becoming hidden.
                visibleOffset: Offset.zero,
                hiddenOffset: const Offset(0, -0.10),
              ),
              _HoverSwapText(
                visible: active,
                text: widget.subtitle,
                style: style,
                maxLines: _labelMaxLines,
                // Subtitle slides up slightly when becoming visible.
                visibleOffset: Offset.zero,
                hiddenOffset: const Offset(0, 0.12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = widget.onTap != null;
    final active = enabled && (_hovered || _pressed);

    final bg = active
        ? cs.primary.withValues(alpha: 0.22)
        : Colors.white.withValues(alpha: 0.10);
    final border = active
        ? cs.primary.withValues(alpha: 0.62)
        : Colors.white.withValues(alpha: 0.18);

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.title,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: GestureDetector(
          onTap: widget.onTap,
          onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
          onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              color: bg,
              border: Border.all(color: border),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: active ? cs.primary.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.10),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
                  ),
                  child: AnimatedScale(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    scale: active ? 1.02 : 1.0,
                    child: Icon(widget.icon, color: Colors.white),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _buildAnimatedLabel(context, active: active),
                ),
                const SizedBox(width: AppSpacing.sm),
                Icon(widget.trailingIcon, color: Colors.white.withValues(alpha: enabled ? 0.92 : 0.55)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HoverSwapText extends StatelessWidget {
  final bool visible;
  final String text;
  final TextStyle? style;
  final int maxLines;
  final Offset visibleOffset;
  final Offset hiddenOffset;

  const _HoverSwapText({
    required this.visible,
    required this.text,
    required this.style,
    required this.maxLines,
    required this.visibleOffset,
    required this.hiddenOffset,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: true,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: AnimatedSlide(
          offset: visible ? visibleOffset : hiddenOffset,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: Text(
            text,
            style: style,
            maxLines: maxLines,
            overflow: TextOverflow.clip,
            softWrap: true,
          ),
        ),
      ),
    );
  }
}

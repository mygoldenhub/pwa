import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:pwa/nav.dart';
import 'package:pwa/theme.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  // IMPORTANT: This must exist under your project's Assets panel.
  // Upload the file to: assets/images/
  static const String _bgAsset = 'assets/images/94515d5c-1758-4066-a026-5f96a44abfd7.png';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              _bgAsset,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                debugPrint('WelcomePage background asset missing: $_bgAsset. Error: $error');
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
                  child: Column(
                    children: [
                      const SizedBox(height: AppSpacing.sm),
                      const _WelcomeBrandHeader(),
                      const Spacer(),
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
                    ],
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
          const _TileTradeMark(),
          const SizedBox(height: AppSpacing.sm),
          Text('Scan & Go', style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'STAFFLESS STORE',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.80),
              letterSpacing: 1.2,
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

class _TileTradeMark extends StatelessWidget {
  const _TileTradeMark();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final onDark = Colors.white;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 54,
          height: 54,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: const _FourTiles(),
        ),
        const SizedBox(width: AppSpacing.md),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('TILE TRADE', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: onDark, letterSpacing: 0.6)),
            const SizedBox(height: 2),
            Text(
              'STAFFLESS STORE',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: onDark.withValues(alpha: 0.75),
                letterSpacing: 1.1,
              ),
            ),
          ],
        ),
        const SizedBox(width: 2),
        Icon(Icons.qr_code_scanner, color: cs.primary.withValues(alpha: 0.95), size: 22),
      ],
    );
  }
}

class _FourTiles extends StatelessWidget {
  const _FourTiles();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = 6.0;
        final size = (constraints.maxWidth - gap) / 2;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            SizedBox(width: size, height: size, child: _MarkTile(color: Colors.white)),
            SizedBox(width: size, height: size, child: _MarkTile(color: Colors.white)),
            SizedBox(width: size, height: size, child: _MarkTile(color: cs.primary.withValues(alpha: 0.95))),
            SizedBox(width: size, height: size, child: _MarkTile(color: cs.primary.withValues(alpha: 0.95))),
          ],
        );
      },
    );
  }
}

class _MarkTile extends StatelessWidget {
  final Color color;
  const _MarkTile({required this.color});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
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

    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, AppSpacing.lg),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: cs.outline.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Welcome!', style: Theme.of(context).textTheme.headlineSmall?.semiBold, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Access your trade account\nor create a new one to start shopping.',
            style: Theme.of(context).textTheme.bodyMedium?.withColor(cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            onPressed: onExistingAccount,
            icon: Icon(Icons.person, color: cs.onPrimary),
            label: Text('Existing Trade Account', style: TextStyle(color: cs.onPrimary)),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16)),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Sign in to access your account and shop.',
            style: Theme.of(context).textTheme.bodySmall?.withColor(cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.md),
          const _OrDivider(),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: onCreateAccount,
            icon: Icon(Icons.person_add_alt_1, color: AppSemanticColors.success),
            label: Text('New Customer / Create Account', style: const TextStyle(color: AppSemanticColors.success)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppSemanticColors.success.withValues(alpha: 0.55)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Create a new account to get started.',
            style: Theme.of(context).textTheme.bodySmall?.withColor(cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.md),
          Center(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Need help? ', style: Theme.of(context).textTheme.bodySmall?.withColor(cs.onSurfaceVariant)),
                TextButton(
                  onPressed: () {},
                  child: Text('Contact support', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.primary)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.labelSmall?.withColor(cs.onSurfaceVariant);

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

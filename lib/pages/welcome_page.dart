import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pwa/nav.dart';
import 'package:pwa/theme.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: AppSpacing.paddingLg,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: AppSpacing.paddingXl,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.xl),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [cs.primaryContainer, cs.surfaceContainerHighest],
                      ),
                      border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 74,
                          height: 74,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(26),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [cs.primary, cs.tertiary],
                            ),
                          ),
                          child: const Icon(Icons.qr_code_scanner, color: Colors.white, size: 34),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text('Welcome!', style: Theme.of(context).textTheme.headlineSmall?.semiBold),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Scan & go trade portal. Sign in to manage products and check out faster.',
                          style: Theme.of(context).textTheme.bodyMedium?.withColor(cs.onSurfaceVariant),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => context.go(AppRoutes.login),
                      icon: Icon(Icons.login, color: cs.onPrimary),
                      label: Text('Login', style: TextStyle(color: cs.onPrimary)),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => context.go(AppRoutes.register),
                      icon: Icon(Icons.person_add_alt_1, color: cs.primary),
                      label: Text('Create account', style: TextStyle(color: cs.primary)),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Tip: If you just created an account, check your email for an 8-digit verification code.',
                    style: Theme.of(context).textTheme.bodySmall?.withColor(cs.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

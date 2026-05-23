import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pwa/app_state.dart';
import 'package:pwa/components/app_logo.dart';
import 'package:pwa/nav.dart';
import 'package:pwa/theme.dart';

class AccountPage extends StatelessWidget {
  final AppState appState;
  const AccountPage({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final user = appState.auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 240,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Center(
            child: GestureDetector(
              onTap: () => context.go(AppRoutes.welcome),
              child: const AppCornerBrand(logoSize: 42),
            ),
          ),
        ),
        title: const Text('Account'),
      ),
      body: SafeArea(
        child: Padding(
          padding: AppSpacing.paddingLg,
          child: Column(
            children: [
              Container(
                padding: AppSpacing.paddingLg,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  color: cs.surface,
                  border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadius.xl),
                        color: cs.primaryContainer,
                      ),
                      child: Icon(Icons.person, color: cs.onPrimaryContainer),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.displayName ?? 'Guest',
                            style: Theme.of(context).textTheme.titleLarge?.semiBold,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            user?.email ?? 'Not signed in',
                            style:
                                Theme.of(context).textTheme.bodyMedium?.withColor(cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async {
                    await appState.auth.signOut();
                    if (context.mounted) context.go(AppRoutes.login);
                  },
                  style: FilledButton.styleFrom(backgroundColor: cs.error),
                  icon: Icon(Icons.logout, color: cs.onError),
                  label: Text('Sign out', style: TextStyle(color: cs.onError)),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Later: add roles (admin/customer) and sync accounts to Supabase/Firebase.',
                style: Theme.of(context).textTheme.bodySmall?.withColor(cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

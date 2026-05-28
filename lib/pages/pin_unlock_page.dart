import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pwa/app_state.dart';
import 'package:pwa/components/auth_scaffold.dart';
import 'package:pwa/nav.dart';
import 'package:pwa/theme.dart';

/// Deprecated page.
///
/// PIN-unlock gating was removed from the app, but we keep this widget around
/// to avoid breaking old deep links / cached routes.
class PinUnlockPage extends StatelessWidget {
  final AppState appState;
  const PinUnlockPage({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      context.go(appState.auth.isSignedIn ? AppRoutes.cart : AppRoutes.welcome);
    });

    return AuthScaffold(
      title: 'Redirecting',
      subtitle: 'PIN unlock is no longer required.',
      icon: Icons.verified_user_outlined,
      showBack: false,
      child: const Padding(
        padding: EdgeInsets.only(top: AppSpacing.md),
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pwa/app_state.dart';
import 'package:pwa/nav.dart';
import 'package:pwa/supabase/supabase_config.dart';

/// Handles Supabase email confirmation redirect on Flutter web/PWA.
///
/// Supabase will redirect the user to this path with auth parameters in the URL.
/// We then finalize the session and send them into the app.
class AuthCallbackPage extends StatefulWidget {
  final AppState appState;
  const AuthCallbackPage({super.key, required this.appState});

  @override
  State<AuthCallbackPage> createState() => _AuthCallbackPageState();
}

class _AuthCallbackPageState extends State<AuthCallbackPage> {
  bool _didRun = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didRun) return;
    _didRun = true;
    _completeAuthFromUrl();
  }

  Future<void> _completeAuthFromUrl() async {
    try {
      // On web, Supabase places tokens in the URL fragment/query; this call extracts
      // them and sets the session.
      await SupabaseConfig.auth.getSessionFromUrl(Uri.base);

      // Give AppState/AuthService a brief moment to receive onAuthStateChange.
      await Future<void>.delayed(const Duration(milliseconds: 150));

      if (!mounted) return;
      context.go(widget.appState.auth.isSignedIn ? AppRoutes.cart : AppRoutes.login);
    } catch (e) {
      debugPrint('AuthCallbackPage: failed to complete auth from URL: $e');
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  SizedBox(
                    width: 42,
                    height: 42,
                    child: CircularProgressIndicator(color: cs.primary),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _error == null ? 'Finishing sign-in…' : 'We couldn\'t finish signing you in',
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.error),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => context.go(AppRoutes.login),
                        icon: Icon(Icons.login, color: cs.onPrimary),
                        label: Text('Back to login', style: TextStyle(color: cs.onPrimary)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

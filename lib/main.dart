import 'package:flutter/material.dart';
import 'package:pwa/app_state.dart';
import 'package:pwa/nav.dart';
import 'package:pwa/services/auth_service.dart';
import 'package:pwa/services/product_service.dart';
import 'package:pwa/supabase/supabase_config.dart';
import 'package:pwa/theme.dart';

/// Main entry point for the application
///
/// This sets up:
/// - go_router navigation
/// - Material 3 theming with light/dark modes
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Ensure Supabase client is ready for any auth/database usage.
  // (Safe to call even if you're still using local-only services for now.)
  try {
    await SupabaseConfig.initialize();
  } catch (e) {
    debugPrint('Supabase initialization failed (app will continue): $e');
  }

  final appState = AppState(auth: AuthService(), products: ProductService());
  await appState.init();
  runApp(MyApp(appState: appState));
}

class MyApp extends StatelessWidget {
  final AppState appState;
  const MyApp({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    // As you extend the app, use MultiProvider to wrap the app
    // and provide state to all widgets
    // Example:
    // return MultiProvider(
    //   providers: [
    //     ChangeNotifierProvider(create: (_) => ExampleProvider()),
    //   ],
    //   child: MaterialApp.router(
    //     title: 'Dreamflow Starter',
    //     debugShowCheckedModeBanner: false,
    //     routerConfig: AppRouter.router,
    //   ),
    // );
    return MaterialApp.router(
      title: 'Dreamflow Starter',
      debugShowCheckedModeBanner: false,

      // Theme configuration
      theme: lightTheme,
      darkTheme: darkTheme,
      // Force light mode for now to match the requested white UI.
      themeMode: ThemeMode.light,

      // Router configuration
      routerConfig: AppRouter.createRouter(appState),
    );
  }
}

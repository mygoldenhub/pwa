import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pwa/app_state.dart';
import 'package:pwa/pages/account_page.dart';
import 'package:pwa/pages/app_shell_page.dart';
import 'package:pwa/pages/auth_callback_page.dart';
import 'package:pwa/pages/barcode_scanner_page.dart';
import 'package:pwa/pages/barcode_result_page.dart';
import 'package:pwa/pages/invoice_page.dart';
import 'package:pwa/pages/invoice_success_page.dart';
import 'package:pwa/pages/loading_page.dart';
import 'package:pwa/pages/login_page.dart';
import 'package:pwa/pages/products_page.dart';
import 'package:pwa/pages/register_page.dart';
import 'package:pwa/pages/reset_password_page.dart';
import 'package:pwa/pages/new_password_page.dart';
import 'package:pwa/pages/verify_email_code_page.dart';
import 'package:pwa/pages/welcome_page.dart';
import 'package:pwa/pages/xero_product_detail_page.dart';
import 'package:pwa/pages/product_form_page.dart';
import 'package:pwa/pages/stripe_checkout_success_page.dart';

/// GoRouter configuration for app navigation
///
/// This uses go_router for declarative routing, which provides:
/// - Type-safe navigation
/// - Deep linking support (web URLs, app links)
/// - Easy route parameters
/// - Navigation guards and redirects
///
/// To add a new route:
/// 1. Add a route constant to AppRoutes below
/// 2. Add a GoRoute to the routes list
/// 3. Navigate using context.go() or context.push()
/// 4. Use context.pop() to go back.
class AppRouter {
  static GoRouter createRouter(AppState appState) {
    return GoRouter(
      initialLocation: AppRoutes.loading,
      refreshListenable: appState,
      redirect: (context, state) {
        // Use path for comparisons so query params (e.g. ?flow=recovery) don't break guards.
        final path = state.uri.path;
        final ready = appState.isReady;
        final signedIn = appState.auth.isSignedIn;

        final isLoading = path == AppRoutes.loading;
        final isAuth = path == AppRoutes.welcome || path == AppRoutes.login || path == AppRoutes.register || path == AppRoutes.verifyEmail || path == AppRoutes.resetPassword;
        final isApp = path.startsWith('/app');

        final isRecoveryFlow = state.uri.queryParameters['flow'] == 'recovery';

        if (!ready && !isLoading) return AppRoutes.loading;
        if (ready && isLoading) return signedIn ? AppRoutes.cart : AppRoutes.welcome;
        if (!signedIn && isApp) return AppRoutes.welcome;
        // Allow navigating to the New Password page during the recovery flow.
        // Supabase may not reflect a signed-in session immediately in appState, but the UI
        // should still be able to reach this route after OTP verification.
        if (signedIn && isAuth && !isRecoveryFlow) return AppRoutes.cart;
        return null;
      },
      routes: [
        GoRoute(
          path: AppRoutes.loading,
          pageBuilder: (context, state) => const NoTransitionPage(child: LoadingPage()),
        ),
        GoRoute(
          path: AppRoutes.authCallback,
          pageBuilder: (context, state) => NoTransitionPage(child: AuthCallbackPage(appState: appState)),
        ),
        GoRoute(
          path: AppRoutes.login,
          pageBuilder: (context, state) => NoTransitionPage(child: LoginPage(appState: appState)),
        ),
        GoRoute(
          path: AppRoutes.resetPassword,
          pageBuilder: (context, state) {
            final email = state.uri.queryParameters['email'];
            return NoTransitionPage(child: ResetPasswordPage(appState: appState, initialEmail: email));
          },
        ),
        GoRoute(
          path: AppRoutes.newPassword,
          pageBuilder: (context, state) {
            final extra = (state.extra is Map) ? (state.extra as Map) : const <String, dynamic>{};
            return NoTransitionPage(
              child: NewPasswordPage(
                appState: appState,
                email: (extra['email'] ?? '').toString(),
              ),
            );
          },
        ),
        GoRoute(
          path: AppRoutes.welcome,
          pageBuilder: (context, state) => NoTransitionPage(child: WelcomePage(appState: appState)),
        ),
        GoRoute(
          path: AppRoutes.register,
          pageBuilder: (context, state) => NoTransitionPage(child: RegisterPage(appState: appState)),
        ),
        GoRoute(
          path: AppRoutes.verifyEmail,
          pageBuilder: (context, state) {
            final extra = (state.extra is Map) ? (state.extra as Map) : const <String, dynamic>{};
            return NoTransitionPage(
              child: VerifyEmailCodePage(
                appState: appState,
                email: (extra['email'] ?? '').toString(),
                displayName: (extra['displayName'] ?? '').toString(),
                companyName: (extra['companyName'] ?? '').toString(),
                phoneNumber: (extra['phoneNumber'] ?? '').toString(),
                password: (extra['password'] ?? '').toString(),
                pin: (extra['pin'] ?? '').toString(),
              ),
            );
          },
        ),
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) => AppShellPage(navigationShell: navigationShell),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: AppRoutes.cart,
                  pageBuilder: (context, state) => NoTransitionPage(
                    child: ProductsPage(appState: appState),
                  ),
                  routes: [
                    GoRoute(
                      path: 'scan',
                      pageBuilder: (context, state) => MaterialPage(
                        key: state.pageKey,
                        child: const BarcodeScannerPage(),
                      ),
                    ),
                    GoRoute(
                      path: 'barcode/:barcode',
                      pageBuilder: (context, state) {
                        final barcode = Uri.decodeComponent(state.pathParameters['barcode'] ?? '');
                        return MaterialPage(child: BarcodeResultPage(barcode: barcode));
                      },
                    ),
                    GoRoute(
                      path: 'new',
                      pageBuilder: (context, state) {
                        final extra = (state.extra is Map) ? (state.extra as Map) : const <String, dynamic>{};
                        return MaterialPage(
                          child: ProductFormPage(
                            appState: appState,
                            productId: null,
                            initialBarcode: (extra['initial_barcode'] ?? '').toString(),
                            initialName: (extra['initial_name'] ?? '').toString(),
                          ),
                        );
                      },
                    ),
                    GoRoute(
                      path: 'xero/:xeroItemId',
                      pageBuilder: (context, state) => MaterialPage(
                        child: XeroProductDetailPage(xeroItemId: state.pathParameters['xeroItemId'] ?? ''),
                      ),
                    ),
                    GoRoute(
                      path: ':id/edit',
                      pageBuilder: (context, state) => MaterialPage(
                        child: ProductFormPage(appState: appState, productId: state.pathParameters['id']),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: AppRoutes.invoice,
                  pageBuilder: (context, state) {
                    final extra = (state.extra is Map) ? (state.extra as Map) : const <String, dynamic>{};
                    return NoTransitionPage(child: InvoicePage(draft: extra['draft'], webhook: extra['webhook']));
                  },
                  routes: [
                    GoRoute(
                      path: 'success/:invoiceId',
                      pageBuilder: (context, state) {
                        final invoiceId = state.pathParameters['invoiceId'];
                        final discountRaw = state.uri.queryParameters['discount'];
                        final discount = discountRaw == null ? null : double.tryParse(discountRaw);
                        return MaterialPage(
                          child: InvoiceSuccessPage(
                            invoiceId: invoiceId ?? '',
                            discountPercent: discount,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: AppRoutes.account,
                  pageBuilder: (context, state) => NoTransitionPage(
                    child: AccountPage(appState: appState),
                  ),
                ),
              ],
            ),
          ],
        ),

        // Stripe redirect return page (hosted checkout -> success_url)
        GoRoute(
          path: AppRoutes.stripeCheckoutSuccess,
          pageBuilder: (context, state) {
            final sessionId = state.uri.queryParameters['session_id'] ?? '';
            return MaterialPage(child: StripeCheckoutSuccessPage(sessionId: sessionId));
          },
        ),
      ],
    );
  }
}

/// Route path constants
/// Use these instead of hard-coding route strings
class AppRoutes {
  static const String loading = '/loading';
  static const String authCallback = '/auth/callback';
  static const String welcome = '/welcome';
  static const String login = '/login';
  static const String resetPassword = '/reset-password';
  static const String newPassword = '/new-password';
  static const String register = '/register';
  static const String verifyEmail = '/verify-email';

  static const String cart = '/app/cart';
  static const String invoice = '/app/invoice';
  static String invoiceSuccess(String invoiceId, {num? discount}) {
    final base = '/app/invoice/success/${Uri.encodeComponent(invoiceId)}';
    if (discount == null) return base;
    return '$base?discount=${Uri.encodeComponent(discount.toString())}';
  }
  static const String account = '/app/account';

  static const String stripeCheckoutSuccess = '/app/stripe/success';

  static const String barcodeScan = '/app/cart/scan';
  static String barcodeResult(String barcode) =>
      '/app/cart/barcode/${Uri.encodeComponent(barcode)}';
  static const String productNew = '/app/cart/new';
  static String productEdit(String id) => '/app/cart/$id/edit';
  static String xeroProduct(String xeroItemId) => '/app/cart/xero/$xeroItemId';
}

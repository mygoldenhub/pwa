import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pwa/app_state.dart';
import 'package:pwa/components/app_header.dart';
import 'package:pwa/components/new_invoice_sheet.dart';
import 'package:pwa/components/quantity_input.dart';
import 'package:pwa/models/cart_item.dart';
import 'package:pwa/models/xero_product.dart';
import 'package:pwa/nav.dart';
import 'package:pwa/services/cart_service.dart';
import 'package:pwa/services/invoice_webhook_service.dart';
import 'package:pwa/services/pending_invoice_storage.dart';
import 'package:pwa/services/stripe_checkout_service.dart';
import 'package:pwa/services/xero_product_service.dart';
import 'package:pwa/theme.dart';
import 'package:url_launcher/url_launcher.dart';

class ProductsPage extends StatefulWidget {
  final AppState appState;
  const ProductsPage({super.key, required this.appState});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

enum _ScanChoice { barcode, productName }

/// Shared “modal” surface used by overlays in this page.
///
/// We use a center-screen dialog presentation (not a bottom-sheet) so:
/// - it appears in the middle of the screen
/// - there is no drag handle (“------”) at the top
/// - it behaves consistently across mobile/web
class AppModalSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadiusGeometry borderRadius;
  const AppModalSurface({super.key, required this.child, this.padding = const EdgeInsets.all(AppSpacing.lg), this.borderRadius = const BorderRadius.all(Radius.circular(AppRadius.xl))});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Important: don't wrap with Center here.
    // A full-screen Center/Align is hit-testable and can prevent the route's
    // modal barrier from receiving outside taps (breaking tap-to-dismiss).
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Material(
        color: cs.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: borderRadius),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class AppCenteredModalDialog extends StatelessWidget {
  final Widget child;
  const AppCenteredModalDialog({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      child: child,
    );
  }
}

class _ScanChoiceSheet extends StatelessWidget {
  const _ScanChoiceSheet();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppModalSurface(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add item', style: Theme.of(context).textTheme.titleLarge?.semiBold),
          const SizedBox(height: AppSpacing.xs),
          Text('Choose how you want to add an item.', style: Theme.of(context).textTheme.bodyMedium?.withColor(cs.onSurfaceVariant)),
          const SizedBox(height: AppSpacing.lg),
          _ScanChoiceTile(
            icon: Icons.qr_code_scanner,
            title: 'Barcode mode',
            subtitle: 'Use your camera to scan a barcode.',
            onTap: () => Navigator.of(context).pop(_ScanChoice.barcode),
          ),
          const SizedBox(height: AppSpacing.md),
          _ScanChoiceTile(
            icon: Icons.text_fields,
            title: 'Product name mode',
            subtitle: 'Enter the item name manually.',
            onTap: () => Navigator.of(context).pop(_ScanChoice.productName),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }
}

class _ScanChoiceTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ScanChoiceTile({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  State<_ScanChoiceTile> createState() => _ScanChoiceTileState();
}

class _ScanChoiceTileState extends State<_ScanChoiceTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          padding: AppSpacing.paddingLg,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            color: _hovered ? cs.primaryContainer.withValues(alpha: 0.55) : cs.surface,
            border: Border.all(color: _hovered ? cs.primary.withValues(alpha: 0.35) : cs.outline.withValues(alpha: 0.12)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: Icon(widget.icon, color: cs.onPrimaryContainer),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title, style: Theme.of(context).textTheme.titleMedium?.semiBold),
                    const SizedBox(height: 2),
                    Text(widget.subtitle, style: Theme.of(context).textTheme.bodySmall?.withColor(cs.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductsPageState extends State<ProductsPage> {
  String _query = '';
  bool _handledRouteExtra = false;

  // Optimistic cart UI overrides so the summary updates instantly, without
  // waiting for the Supabase stream round-trip.
  final Map<String, int> _qtyOverrides = <String, int>{};
  final Set<String> _pendingRemovals = <String>{};

  void _showSavedNotification() {
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          showCloseIcon: true,
          margin: const EdgeInsets.all(AppSpacing.lg),
          content: Row(
            children: [
              Icon(Icons.check_circle_outline, color: cs.onInverseSurface),
              const SizedBox(width: AppSpacing.sm),
              const Expanded(child: Text('Product saved')),
            ],
          ),
        ),
      );
  }


  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Handle one-time route extras (e.g. ProductFormPage navigates back with
    // extra: {'product_saved': true}). We clear it via replace to prevent the
    // snackbar from reappearing on rebuilds / refresh.
    if (_handledRouteExtra) return;
    final extra = GoRouterState.of(context).extra;
    final isSaved = extra is Map && extra['product_saved'] == true;
    if (isSaved) {
      _handledRouteExtra = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showSavedNotification();
        context.replace(AppRoutes.cart);
      });
    }
  }

  Future<void> _openViaBarcode() async {
    await context.push(AppRoutes.barcodeScan);
  }

  Future<void> _openViaProductName() async {
    final cs = Theme.of(context).colorScheme;
    final selected = await showDialog<XeroProduct>(
      context: context,
      barrierDismissible: true,
      barrierColor: cs.scrim.withValues(alpha: 0.52),
      builder: (context) => AppCenteredModalDialog(child: _XeroProductNamePickerSheet(initialQuery: _query.trim())),
    );
    if (!mounted || selected == null) return;
    context.push(AppRoutes.xeroProduct(selected.xeroItemId));
  }

  Future<void> _openScanChooser() async {
    final cs = Theme.of(context).colorScheme;
    // Use an explicitly dismissible dialog route so tapping outside the modal
    // always closes it (especially on web where nested navigators can make
    // dismissal feel inconsistent).
    final choice = await showGeneralDialog<_ScanChoice>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: cs.scrim.withValues(alpha: 0.52),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, animation, secondaryAnimation) {
        // Some full-screen widgets (e.g. Center/Align) can swallow taps, making
        // the framework barrier dismiss unreliable. We add an explicit
        // tap-to-dismiss layer to guarantee the desired behavior.
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: const SizedBox.shrink(),
              ),
            ),
            const Center(child: AppCenteredModalDialog(child: _ScanChoiceSheet())),
          ],
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.98, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );

    if (!mounted || choice == null) return;
    switch (choice) {
      case _ScanChoice.barcode:
        await _openViaBarcode();
      case _ScanChoice.productName:
        await _openViaProductName();
    }
  }

  Future<void> _openNewInvoiceSheet({required int totalBudgetCents, required List<CartItem> cartItems}) async {
    final cs = Theme.of(context).colorScheme;
    final draft = await showDialog<InvoiceDraft>(
      context: context,
      barrierDismissible: true,
      barrierColor: cs.scrim.withValues(alpha: 0.52),
      builder: (context) => AppCenteredModalDialog(
        child: AppModalSurface(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: NewInvoiceSheet(totalBudgetCents: totalBudgetCents),
        ),
      ),
    );
    if (!mounted || draft == null) return;

    // Requirement: Ask “Pay now?” immediately after the user taps Create,
    // without running the invoice-creation logic first.
    final payNow = await _confirmPayNow();
    if (!mounted) return;

    // If user closes the dialog (X or tap outside), do nothing.
    if (payNow == null) return;

    if (payNow) {
      await _startStripeCheckout(draft: draft, cartItems: cartItems);
      return;
    }

    await _createInvoice(draft: draft, cartItems: cartItems);
  }

  Future<bool?> _confirmPayNow() async {
    final cs = Theme.of(context).colorScheme;
    final choice = await showDialog<bool?>(
      context: context,
      barrierDismissible: true,
      barrierColor: cs.scrim.withValues(alpha: 0.52),
      builder: (context) => AppCenteredModalDialog(
        child: AppModalSurface(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(AppRadius.lg)),
                    child: Icon(Icons.payments_outlined, color: cs.onSecondaryContainer),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: Text('Pay now?', style: Theme.of(context).textTheme.titleLarge?.semiBold)),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(null),
                    icon: Icon(Icons.close, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Pay now or charge account please.',
                style: Theme.of(context).textTheme.bodyMedium?.withColor(cs.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(true),
                      icon: Icon(Icons.lock_outline, color: cs.onPrimary),
                      label: Text('Now', style: TextStyle(color: cs.onPrimary)),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).pop(false),
                      icon: Icon(Icons.schedule, color: cs.onSurface),
                      label: Text('Later', style: TextStyle(color: cs.onSurface)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return choice;
  }

  Future<void> _launchCheckoutUrl(Uri url) async {
    try {
      final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!ok) throw 'Could not open Stripe Checkout.';
    } catch (e) {
      debugPrint('Failed to launch Stripe checkout URL: $e');
      rethrow;
    }
  }

  Future<void> _startStripeCheckout({required InvoiceDraft draft, required List<CartItem> cartItems}) async {
    final cs = Theme.of(context).colorScheme;

    // Save cart + invoice draft locally so we can create the invoice after
    // Stripe checkout completes (even after refresh/deep-link).
    try {
      final contactId = widget.appState.auth.currentUser?.xeroAccountId?.trim() ?? '';
      final payload = <String, dynamic>{
        'reference': draft.reference,
        'currency_code': draft.currencyCode,
        'currency_rate': draft.currencyRate,
        'line_amount_type': InvoiceWebhookService.lineAmountTypeApi(draft.lineAmountType),
        'date': InvoiceWebhookService.fmtDate(draft.date),
        'due_date': InvoiceWebhookService.fmtDate(draft.dueDate),
        'contactID': contactId,
        'products': cartItems.map((c) {
          final unitAmount = (c.unitPriceCents ?? 0) / 100.0;
          return <String, dynamic>{
            'item': c.productName,
            'description': c.productName,
            'quantity': c.quantity,
            'unit amount': unitAmount,
          };
        }).toList(),
      };
      await PendingInvoiceStorage.save(payload);
    } catch (e) {
      debugPrint('Failed to save pending invoice payload: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              showCloseIcon: true,
              margin: const EdgeInsets.all(AppSpacing.lg),
              content: const Text('Could not save the cart for payment. Please try again.'),
            ),
          );
      }
      return;
    }

    // Small blocking progress dialog.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: cs.scrim.withValues(alpha: 0.52),
      builder: (context) => const AppCenteredModalDialog(
        child: AppModalSurface(
          child: Row(
            children: [
              SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
              SizedBox(width: AppSpacing.md),
              Expanded(child: Text('Opening Stripe Checkout…')),
            ],
          ),
        ),
      ),
    );

    try {
      final currency = draft.currencyCode;
      final lineItems = cartItems
          .where((c) => c.productName.trim().isNotEmpty)
          .map((c) => (name: c.productName.trim(), unitAmountCents: c.unitPriceCents ?? 0, quantity: c.quantity))
          .toList();

      // IMPORTANT: Stripe amount must include tax.
      // This cart flow uses `LineAmountType.exclusive`, so we add GST as a separate line item.
      final subtotalCents = cartItems.fold<int>(0, (sum, c) => sum + (c.unitPriceCents ?? 0) * c.quantity);
      final gstCents = (subtotalCents * 0.10).round();
      final lineItemsWithTax = <({String name, int unitAmountCents, int quantity})>[...lineItems];
      if (gstCents > 0) {
        lineItemsWithTax.add((name: 'GST (10%)', unitAmountCents: gstCents, quantity: 1));
      }

      final checkoutUrl = await StripeCheckoutService.createHostedCheckoutUrl(
        currency: currency,
        reference: draft.reference,
        invoiceId: null,
        lineItems: lineItemsWithTax,
        customerEmail: widget.appState.auth.currentUser?.email,
      );

      if (!mounted) return;
      context.pop(); // close loading
      // IMPORTANT:
      // Do NOT clear the cart here.
      // The user has only *started* the payment flow; the invoice is not created
      // yet and the payment might still fail/cancel.
      await _launchCheckoutUrl(checkoutUrl);
    } catch (e) {
      debugPrint('_startStripeCheckout failed: $e');
      if (mounted) {
        context.pop(); // close loading
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              showCloseIcon: true,
              margin: const EdgeInsets.all(AppSpacing.lg),
              content: Text('Failed to start Stripe Checkout: ${e.toString()}'),
            ),
          );
      }
    }
  }

  Future<void> _createInvoice({required InvoiceDraft draft, required List<CartItem> cartItems}) async {
    final cs = Theme.of(context).colorScheme;
    final contactId = widget.appState.auth.currentUser?.xeroAccountId?.trim() ?? '';
    if (contactId.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Missing Xero contactID. Please set users.xero_account_id first.')),
        );
      return;
    }

    // Show a small blocking progress dialog.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: cs.scrim.withValues(alpha: 0.52),
      builder: (context) => const AppCenteredModalDialog(
        child: AppModalSurface(
          child: Row(
            children: [
              SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
              SizedBox(width: AppSpacing.md),
              Expanded(child: Text('Creating invoice…')),
            ],
          ),
        ),
      ),
    );

    try {
      // Enrich cart items with product details (account code, tax code, description, etc.).
      final uniqueIds = cartItems.map((c) => c.xeroItemId).where((s) => s.trim().isNotEmpty).toSet().toList();
      final products = await Future.wait(uniqueIds.map(XeroProductService.getByXeroItemId));
      final map = <String, XeroProduct?>{};
      for (var i = 0; i < uniqueIds.length; i++) {
        map[uniqueIds[i]] = products[i];
      }

      final result = await InvoiceWebhookService.createInvoice(
        draft: draft,
        cartItems: cartItems,
        productsByItemId: map,
        contactId: contactId,
      );

      if (!mounted) return;
      context.pop(); // close loading

      // Webhook succeeded. Clear the customer's cart before going to Invoice Draft.
      try {
        await CartService.clearMyCart();
      } catch (e) {
        debugPrint('Failed to clear cart after invoice creation: $e');
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                behavior: SnackBarBehavior.floating,
                showCloseIcon: true,
                margin: const EdgeInsets.all(AppSpacing.lg),
                content: const Text('Invoice created, but failed to clear your cart. Please refresh and try again.'),
              ),
            );
        }
      }

      // Navigate to a success page (after webhook success + cart clear).
      final createdInvoiceId = result.body;
      debugPrint('--------createdInvoiceId--------');
      debugPrint('$createdInvoiceId');
      debugPrint('--------createdInvoiceId--------');
      if (createdInvoiceId == null || createdInvoiceId.toString().trim().isEmpty) {
        throw Exception('Invoice was created, but no invoice id was returned from the webhook.');
      }
      context.go(AppRoutes.invoiceSuccess(createdInvoiceId));
    } catch (e) {
      if (!mounted) return;
      context.pop(); // close loading
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            showCloseIcon: true,
            margin: const EdgeInsets.all(AppSpacing.lg),
            content: Text(e.toString()),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppImpactHeader(
        title: 'Cart',
        actions: [
          _HeaderActionButton(
            label: 'Add product',
            icon: Icons.add,
            onTap: _openScanChooser,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: AppSpacing.paddingLg,
          child: Column(
            children: [
              Expanded(
                child: StreamBuilder<List<CartItem>>(
                  stream: CartService.streamMyCart(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snap.hasError) {
                      debugPrint('ProductsPage(cart): stream error: ${snap.error}');
                      return _EmptyState(
                        title: 'Couldn\'t load cart',
                        subtitle: 'Please try again. If this keeps happening, check your Supabase RLS policies.',
                        onPrimaryAction: _openScanChooser,
                      );
                    }

                    final rawItems = (snap.data ?? <CartItem>[]);

                    // If the stream has removed items we optimistically hid, drop them from the pending set.
                    final rawIds = rawItems.map((e) => e.id).toSet();
                    _pendingRemovals.removeWhere((id) => !rawIds.contains(id));

                    final itemsForList = rawItems
                        .map((i) => _qtyOverrides.containsKey(i.id) ? i.copyWith(quantity: _qtyOverrides[i.id]) : i)
                        .toList();

                    // Exclude pending removals from totals, so summary updates instantly.
                    final itemsForSummary = itemsForList.where((i) => !_pendingRemovals.contains(i.id)).toList();

                    // If the stream has caught up, clear redundant overrides.
                    for (final i in rawItems) {
                      final o = _qtyOverrides[i.id];
                      if (o != null && o == i.quantity) {
                        _qtyOverrides.remove(i.id);
                      }
                    }

                    final visibleItems = itemsForList.where((i) => !_pendingRemovals.contains(i.id)).toList();
                    if (visibleItems.isEmpty) {
                      return _EmptyState(
                        title: 'Your cart is empty',
                        subtitle: 'Scan a barcode to add items.',
                        onPrimaryAction: _openScanChooser,
                      );
                    }

                    final subtotalCents = itemsForSummary.fold<int>(0, (sum, i) => sum + (i.unitPriceCents ?? 0) * i.quantity);
                    final subtotal = (subtotalCents / 100).toStringAsFixed(2);
                    final totalUnits = itemsForSummary.fold<int>(0, (sum, i) => sum + i.quantity);

                    return Column(
                      children: [
                        _CartSummaryCard(
                          subtotal: subtotal,
                          distinctCount: itemsForSummary.length,
                          unitCount: totalUnits,
                          onCheckout: itemsForSummary.isEmpty ? null : () => _openNewInvoiceSheet(totalBudgetCents: subtotalCents, cartItems: itemsForSummary),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Expanded(
                          child: _CartList(
                            items: itemsForList,
                            isDeleting: (id) => _pendingRemovals.contains(id),
                            onSetQty: (item, newQty) async {
                              final q = newQty.clamp(1, 999);
                              if (_pendingRemovals.contains(item.id)) return;
                              if (q == item.quantity) return;

                              final prev = item.quantity;
                              setState(() => _qtyOverrides[item.id] = q);
                              try {
                                await CartService.updateQuantity(cartItemId: item.id, quantity: q);
                              } catch (e) {
                                debugPrint('ProductsPage(cart): update qty failed: $e');
                                if (!mounted) return;
                                setState(() {
                                  if (prev == (rawItems.firstWhere((r) => r.id == item.id, orElse: () => item).quantity)) {
                                    _qtyOverrides.remove(item.id);
                                  } else {
                                    _qtyOverrides[item.id] = prev;
                                  }
                                });
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Failed to update quantity.')),
                                );
                              }
                            },
                            onDelete: (item) async {
                              if (_pendingRemovals.contains(item.id)) return;
                              setState(() => _pendingRemovals.add(item.id));
                              try {
                                await CartService.deleteItem(cartItemId: item.id);
                                // Keep the item hidden until the stream confirms removal.
                                if (!mounted) return;
                                setState(() => _qtyOverrides.remove(item.id));
                              } catch (e) {
                                debugPrint('ProductsPage(cart): delete failed: $e');
                                if (!mounted) return;
                                setState(() => _pendingRemovals.remove(item.id));
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Failed to remove item.')),
                                );
                              }
                            },
                          )
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

}

class _CartSummaryCard extends StatelessWidget {
  final String subtotal;
  final int distinctCount;
  final int unitCount;
  final VoidCallback? onCheckout;
  const _CartSummaryCard({required this.subtotal, required this.distinctCount, required this.unitCount, required this.onCheckout});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: AppSpacing.paddingLg,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: Icon(Icons.shopping_cart, color: cs.onPrimaryContainer),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Cart summary', style: Theme.of(context).textTheme.titleMedium?.semiBold),
                    const SizedBox(height: 2),
                    Text(
                      '$distinctCount product${distinctCount == 1 ? '' : 's'} · $unitCount unit${unitCount == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.bodySmall?.withColor(cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Subtotal', style: Theme.of(context).textTheme.bodySmall?.withColor(cs.onSurfaceVariant)),
                  const SizedBox(height: 2),
                  Text('\$$subtotal', style: Theme.of(context).textTheme.titleLarge?.semiBold),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onCheckout,
              icon: Icon(Icons.payments_outlined, color: cs.onPrimary),
              label: Text('Checkout', style: TextStyle(color: cs.onPrimary)),
              style: FilledButton.styleFrom(
                backgroundColor: cs.primary,
                disabledBackgroundColor: cs.primary.withValues(alpha: 0.35),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CartList extends StatelessWidget {
  final List<CartItem> items;
  final bool Function(String cartItemId) isDeleting;
  final Future<void> Function(CartItem item, int newQty) onSetQty;
  final Future<void> Function(CartItem item) onDelete;

  const _CartList({required this.items, required this.isDeleting, required this.onSetQty, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, index) => _CartItemCard(
        item: items[index],
        isDeleting: isDeleting(items[index].id),
        onSetQty: (q) => onSetQty(items[index], q),
        onDelete: () => onDelete(items[index]),
      ),
    );
  }
}

class _CartItemCard extends StatefulWidget {
  final CartItem item;
  final bool isDeleting;
  final Future<void> Function(int newQty) onSetQty;
  final Future<void> Function() onDelete;
  const _CartItemCard({required this.item, required this.isDeleting, required this.onSetQty, required this.onDelete});

  @override
  State<_CartItemCard> createState() => _CartItemCardState();
}

class _CartItemCardState extends State<_CartItemCard> {
  bool _updating = false;
  Future<void> _setQty(int newQty) async {
    if (_updating || widget.isDeleting) return;
    final q = newQty.clamp(1, 999);
    if (q == widget.item.quantity) return;
    setState(() => _updating = true);
    try {
      await widget.onSetQty(q);
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _delete() async {
    if (widget.isDeleting) return;
    await widget.onDelete();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final priceCents = widget.item.unitPriceCents ?? 0;
    final price = (priceCents / 100).toStringAsFixed(2);
    final qty = widget.item.quantity;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 140),
      opacity: widget.isDeleting ? 0.0 : 1.0,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: widget.isDeleting
            ? const SizedBox.shrink()
            : AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                padding: AppSpacing.paddingLg,
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Avoid IntrinsicHeight + Expanded (can cause under-measured height and bottom overflows).
                    // We still keep the 50/50 split so controls never crowd out product info.
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 1,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.item.productName,
                                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800, fontSize: 18),
                                maxLines: 3,
                                softWrap: true,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                (widget.item.productCode == null || widget.item.productCode!.trim().isEmpty)
                                    ? 'SKU: —'
                                    : 'SKU: ${widget.item.productCode}',
                                style: tt.bodyMedium?.withColor(cs.onSurfaceVariant),
                                maxLines: 2,
                                softWrap: true,
                              ),
                              const SizedBox(height: AppSpacing.md),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '\$$price',
                                  style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          flex: 1,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Align(
                                alignment: Alignment.topRight,
                                child: _QtyStepper(
                                  value: qty,
                                  isLoading: _updating,
                                  onCommitted: _setQty,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Align(
                                alignment: Alignment.bottomRight,
                                child: IconButton(
                                  tooltip: 'Remove',
                                  onPressed: (_updating || widget.isDeleting) ? null : _delete,
                                  style: IconButton.styleFrom(
                                    backgroundColor: cs.surface,
                                    foregroundColor: cs.error,
                                    splashFactory: NoSplash.splashFactory,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                                  ),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
      ),
    );
  }
}

class _QtyStepper extends StatelessWidget {
  final int value;
  final bool isLoading;
  final ValueChanged<int> onCommitted;

  const _QtyStepper({
    required this.value,
    required this.isLoading,
    required this.onCommitted,
  });

  @override
  Widget build(BuildContext context) {
    // The cart card splits space 50/50; on very small screens that can get tight.
    // Scale down prevents RenderFlex overflow while keeping the same visual style.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: QuantityInput(
        value: value,
        min: 1,
        max: 999,
        enabled: true,
        isLoading: isLoading,
        compact: true,
        commitWhileTyping: false,
        onCommitted: onCommitted,
      ),
    );
  }
}

class _HeaderActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _HeaderActionButton({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: cs.primary,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: cs.primary.withValues(alpha: 0.22)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: cs.onPrimary),
              const SizedBox(width: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(color: cs.onPrimary, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onPrimaryAction;

  const _EmptyState({required this.title, required this.subtitle, required this.onPrimaryAction});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          padding: AppSpacing.paddingXl,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [cs.surface, cs.surfaceContainerHighest],
            ),
            border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                ),
                child: Icon(Icons.add_box_outlined, color: cs.onPrimaryContainer),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(title, style: Theme.of(context).textTheme.titleLarge?.semiBold),
              const SizedBox(height: AppSpacing.xs),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.withColor(cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: onPrimaryAction,
                icon: Icon(Icons.add, color: cs.onPrimary),
                label: Text('Add product', style: TextStyle(color: cs.onPrimary)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _XeroProductNamePickerSheet extends StatefulWidget {
  final String initialQuery;
  const _XeroProductNamePickerSheet({required this.initialQuery});

  @override
  State<_XeroProductNamePickerSheet> createState() => _XeroProductNamePickerSheetState();
}

class _XeroProductNamePickerSheetState extends State<_XeroProductNamePickerSheet> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  String _query = '';
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  int _offset = 0;
  static const int _pageSize = 20;
  List<XeroProduct> _results = const [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.initialQuery;
    _query = widget.initialQuery;
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      _kickoffSearch();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_isLoading || _isLoadingMore || !_hasMore) return;
    final pos = _scrollController.position;
    if (pos.maxScrollExtent <= 0) return;
    if (pos.pixels >= pos.maxScrollExtent - 240) {
      _loadMore();
    }
  }

  Future<void> _loadFirstPage() async {
    final q = _query.trim();
    if (q.isEmpty) {
      if (!mounted) return;
      setState(() {
        _results = const [];
        _offset = 0;
        _hasMore = false;
        _isLoading = false;
        _isLoadingMore = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _isLoadingMore = false;
      _offset = 0;
      _hasMore = false;
    });

    final rows = await XeroProductService.searchByNamePrefixPaged(q, limit: _pageSize, offset: 0);
    if (!mounted) return;
    setState(() {
      _results = rows;
      _offset = rows.length;
      _hasMore = rows.length == _pageSize;
      _isLoading = false;
    });
  }

  Future<void> _loadMore() async {
    final q = _query.trim();
    if (q.isEmpty || _isLoading || _isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final rows = await XeroProductService.searchByNamePrefixPaged(q, limit: _pageSize, offset: _offset);
      if (!mounted) return;
      setState(() {
        // De-dupe by id (defensive; pagination should already avoid duplicates).
        final seen = _results.map((e) => e.xeroItemId).toSet();
        final appended = rows.where((r) => r.xeroItemId.isNotEmpty && seen.add(r.xeroItemId)).toList();
        _results = [..._results, ...appended];
        _offset += rows.length;
        _hasMore = rows.length == _pageSize;
      });
    } catch (e) {
      debugPrint('Product name picker loadMore failed: $e');
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  void _kickoffSearch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () async {
      if (!mounted) return;
      await _loadFirstPage();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Give the dialog a predictable height so the results list has room to
    // scroll (instead of sizing itself to content).
    //
    // On small mobile screens, the keyboard can cover the lower part of the
    // dialog. Use the *available* height (minus viewInsets) so the list remains
    // reachable and scroll gestures work as expected.
    final screenH = MediaQuery.sizeOf(context).height;
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final availableH = (screenH - viewInsets.bottom).clamp(0.0, screenH);
    final dialogHeight = (availableH * 0.78).clamp(360.0, screenH * 0.82);

    return SizedBox(
      height: dialogHeight,
      child: AppModalSurface(
        padding: const EdgeInsets.only(left: AppSpacing.lg, right: AppSpacing.lg, bottom: AppSpacing.lg, top: AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('Product name', style: Theme.of(context).textTheme.titleLarge?.semiBold)),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close, color: cs.onSurfaceVariant),
                ),
              ],
            ),
            Text('Start typing to search products in store.', style: Theme.of(context).textTheme.bodyMedium?.withColor(cs.onSurfaceVariant)),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              onChanged: (v) {
                setState(() => _query = v);
                _kickoffSearch();
              },
              decoration: InputDecoration(
                labelText: 'Product name',
                prefixIcon: Icon(Icons.search, color: cs.onSurfaceVariant),
                suffixIcon: _isLoading
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary)),
                      )
                    : (_query.trim().isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear',
                            onPressed: () {
                              _controller.clear();
                              setState(() {
                                _query = '';
                                _results = const [];
                                _offset = 0;
                                _hasMore = false;
                                _isLoadingMore = false;
                              });
                            },
                            icon: Icon(Icons.close, color: cs.onSurfaceVariant),
                          )),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: _query.trim().isEmpty
                    ? const _HintPanel(key: ValueKey('hint'), icon: Icons.lightbulb_outline, text: 'Try searching by product name, like “Ardex FG 8 misty grey”.')
                    : (!_isLoading && _results.isEmpty)
                        ? const _HintPanel(
                            key: ValueKey('empty'),
                            icon: Icons.search_off,
                            text: 'No matches. If you expect products, confirm Xero sync is running and that you have read access to xero_products.',
                          )
                        : ListView.separated(
                            key: const ValueKey('results'),
                            padding: EdgeInsets.zero,
                            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                            controller: _scrollController,
                            primary: false,
                            physics: const BouncingScrollPhysics(),
                            itemCount: _results.length + (_isLoadingMore ? 1 : 0),
                            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                            itemBuilder: (context, index) {
                              if (index >= _results.length) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                                  child: Center(
                                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary)),
                                  ),
                                );
                              }
                              final p = _results[index];
                              return _XeroProductSuggestionTile(product: p, onTap: () => Navigator.of(context).pop(p));
                            },
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HintPanel extends StatelessWidget {
  final IconData icon;
  final String text;
  const _HintPanel({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: AppSpacing.paddingLg,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        color: cs.surface,
        border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Icon(icon, color: cs.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.withColor(cs.onSurfaceVariant))),
        ],
      ),
    );
  }
}

class _XeroProductSuggestionTile extends StatefulWidget {
  final XeroProduct product;
  final VoidCallback onTap;
  const _XeroProductSuggestionTile({required this.product, required this.onTap});

  @override
  State<_XeroProductSuggestionTile> createState() => _XeroProductSuggestionTileState();
}

class _XeroProductSuggestionTileState extends State<_XeroProductSuggestionTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = widget.product;
    final subtitle = <String>[
      if ((p.code ?? '').trim().isNotEmpty) 'Code: ${p.code}',
      if (p.salePriceCents != null) '\$${(p.salePriceCents! / 100).toStringAsFixed(2)}',
    ].join(' · ');

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          padding: AppSpacing.paddingLg,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            color: _hovered ? cs.primaryContainer.withValues(alpha: 0.50) : cs.surface,
            border: Border.all(color: _hovered ? cs.primary.withValues(alpha: 0.30) : cs.outline.withValues(alpha: 0.12)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  color: cs.secondaryContainer,
                ),
                child: Icon(Icons.inventory_2_outlined, color: cs.onSecondaryContainer),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, style: Theme.of(context).textTheme.titleMedium?.semiBold),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.withColor(cs.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pwa/app_state.dart';
import 'package:pwa/components/app_header.dart';
import 'package:pwa/models/cart_item.dart';
import 'package:pwa/models/xero_product.dart';
import 'package:pwa/nav.dart';
import 'package:pwa/services/cart_service.dart';
import 'package:pwa/services/xero_product_service.dart';
import 'package:pwa/theme.dart';

class ProductsPage extends StatefulWidget {
  final AppState appState;
  const ProductsPage({super.key, required this.appState});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

enum _ScanChoice { barcode, productName }

/// Wraps a bottom-sheet child so it sits above the app shell bottom bar while
/// keeping that bar visible.
///
/// This is needed when `showModalBottomSheet` is presented within a nested
/// navigator (e.g. an `AppShellPage` with a bottom navigation bar).
class BottomSheetAboveNavBar extends StatelessWidget {
  final Widget child;
  const BottomSheetAboveNavBar({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottomPadding = mq.padding.bottom + kBottomNavigationBarHeight;

    // Also react to the keyboard so fields remain visible when the sheet is
    // scroll-controlled.
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: bottomPadding + mq.viewInsets.bottom),
      child: child,
    );
  }
}

class _ScanChoiceSheet extends StatelessWidget {
  const _ScanChoiceSheet();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: AppSpacing.paddingLg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add item', style: Theme.of(context).textTheme.titleLarge?.semiBold),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Choose how you want to add an item.',
            style: Theme.of(context).textTheme.bodyMedium?.withColor(cs.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.lg),
          _ScanChoiceTile(
            icon: Icons.qr_code_scanner,
            title: 'Barcode mode',
            subtitle: 'Use your camera to scan a barcode.',
            onTap: () => context.pop(_ScanChoice.barcode),
          ),
          const SizedBox(height: AppSpacing.md),
          _ScanChoiceTile(
            icon: Icons.text_fields,
            title: 'Product name mode',
            subtitle: 'Enter the item name manually.',
            onTap: () => context.pop(_ScanChoice.productName),
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

  void _showDeletedNotification() {
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
              Icon(Icons.delete_outline, color: cs.onInverseSurface),
              const SizedBox(width: AppSpacing.sm),
              const Expanded(child: Text('Product deleted')),
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
    final barcodeOrCode = await context.push<String?>(AppRoutes.barcodeScan);
    if (!mounted || barcodeOrCode == null || barcodeOrCode.trim().isEmpty) return;
    final found = await XeroProductService.getByCode(barcodeOrCode.trim());
    if (!mounted) return;

    if (found == null) {
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
                Icon(Icons.search_off, color: cs.onInverseSurface),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text('No Xero product found for “${barcodeOrCode.trim()}”')),
              ],
            ),
          ),
        );
      return;
    }

    context.push(AppRoutes.xeroProduct(found.xeroItemId));
  }

  Future<void> _openViaProductName() async {
    final selected = await showModalBottomSheet<XeroProduct>(
      context: context,
      // Keep the app shell bottom bar visible. We instead pad the sheet so its
      // content sits *above* the bottom bar.
      useRootNavigator: false,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => BottomSheetAboveNavBar(
        child: _XeroProductNamePickerSheet(initialQuery: _query.trim()),
      ),
    );
    if (!mounted || selected == null) return;
    context.push(AppRoutes.xeroProduct(selected.xeroItemId));
  }

  Future<void> _openScanChooser() async {
    final choice = await showModalBottomSheet<_ScanChoice>(
      context: context,
      // Keep the app shell bottom bar visible. We instead pad the sheet so its
      // content sits *above* the bottom bar.
      useRootNavigator: false,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => const BottomSheetAboveNavBar(child: _ScanChoiceSheet()),
    );

    if (!mounted || choice == null) return;
    switch (choice) {
      case _ScanChoice.barcode:
        await _openViaBarcode();
      case _ScanChoice.productName:
        await _openViaProductName();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppImpactHeader(
        title: 'Cart',
        actions: [
          _HeaderActionButton(
            label: 'Scan',
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
              _SearchBar(
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: AppSpacing.lg),
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

                    final q = _query.trim().toLowerCase();
                    final filtered = q.isEmpty ? itemsForList : _filterAndRankCartItems(itemsForList, q);

                    final visibleFiltered = filtered.where((i) => !_pendingRemovals.contains(i.id)).toList();
                    if (visibleFiltered.isEmpty) {
                      return _EmptyState(
                        title: itemsForSummary.isEmpty ? 'Your cart is empty' : 'No matches',
                        subtitle: itemsForSummary.isEmpty
                            ? 'Scan a barcode or search by product name to add items.'
                            : 'Try a different product name.',
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
                          onCheckout: itemsForSummary.isEmpty ? null : () => context.go(AppRoutes.invoice),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Expanded(
                          child: _CartList(
                            items: filtered,
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

  List<CartItem> _filterAndRankCartItems(List<CartItem> items, String qLower) {
    final prefix = <CartItem>[];
    final contains = <CartItem>[];
    for (final i in items) {
      final name = i.productName.toLowerCase();
      if (name.startsWith(qLower)) {
        prefix.add(i);
      } else if (name.contains(qLower)) {
        contains.add(i);
      }
    }
    prefix.sort((a, b) => a.productName.toLowerCase().compareTo(b.productName.toLowerCase()));
    contains.sort((a, b) => a.productName.toLowerCase().compareTo(b.productName.toLowerCase()));
    return [...prefix, ...contains];
  }
}

class _SearchBar extends StatelessWidget {
  final ValueChanged<String> onChanged;
  const _SearchBar({required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      decoration: const InputDecoration(
        labelText: 'Search by product name',
        prefixIcon: Icon(Icons.search),
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
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.item.productName,
                            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800, fontSize: 18),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            (widget.item.productCode == null || widget.item.productCode!.trim().isEmpty)
                                ? 'SKU: —'
                                : 'SKU: ${widget.item.productCode}',
                            style: tt.bodyMedium?.withColor(cs.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            '\$$price',
                            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _QtyStepper(
                          quantity: qty,
                          isLoading: _updating,
                          onDecrement: () => _setQty(qty - 1),
                          onIncrement: () => _setQty(qty + 1),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        IconButton(
                          tooltip: 'Remove',
                          onPressed: (_updating || widget.isDeleting) ? null : _delete,
                          style: IconButton.styleFrom(
                            backgroundColor: cs.surfaceContainerHighest,
                            foregroundColor: cs.error,
                            splashFactory: NoSplash.splashFactory,
                          ),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _QtyStepper extends StatelessWidget {
  final int quantity;
  final bool isLoading;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  const _QtyStepper({
    required this.quantity,
    required this.isLoading,
    required this.onDecrement,
    required this.onIncrement,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _QtyIconButton(
            icon: Icons.remove,
            enabled: !isLoading && quantity > 1,
            onTap: onDecrement,
          ),
          const SizedBox(width: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
            child: Text(
              '$quantity',
              key: ValueKey(quantity),
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900, fontSize: 18),
            ),
          ),
          const SizedBox(width: 12),
          _QtyIconButton(
            icon: Icons.add,
            enabled: !isLoading && quantity < 999,
            onTap: onIncrement,
          ),
        ],
      ),
    );
  }
}

class _QtyIconButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _QtyIconButton({required this.icon, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      padding: EdgeInsets.zero,
      onPressed: enabled ? onTap : null,
      style: IconButton.styleFrom(
        backgroundColor: cs.surface,
        foregroundColor: enabled ? cs.primary : cs.onSurfaceVariant.withValues(alpha: 0.45),
        splashFactory: NoSplash.splashFactory,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: Icon(icon, size: 18),
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
                label: Text('Scan', style: TextStyle(color: cs.onPrimary)),
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

  String _query = '';
  bool _isLoading = false;
  List<XeroProduct> _results = const [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.initialQuery;
    _query = widget.initialQuery;
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
    super.dispose();
  }

  void _kickoffSearch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () async {
      final q = _query.trim();
      if (!mounted) return;
      if (q.isEmpty) {
        setState(() {
          _results = const [];
          _isLoading = false;
        });
        return;
      }

      setState(() => _isLoading = true);
      final rows = await XeroProductService.searchByNamePrefix(q, limit: 10);
      if (!mounted) return;
      setState(() {
        _results = rows;
        _isLoading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(left: AppSpacing.lg, right: AppSpacing.lg, bottom: bottomInset + AppSpacing.lg, top: AppSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Product name', style: Theme.of(context).textTheme.titleLarge?.semiBold),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Start typing to search products synced from Xero.',
            style: Theme.of(context).textTheme.bodyMedium?.withColor(cs.onSurfaceVariant),
          ),
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
                            });
                          },
                          icon: Icon(Icons.close, color: cs.onSurfaceVariant),
                        )),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_query.trim().isEmpty)
            _HintPanel(icon: Icons.lightbulb_outline, text: 'Try searching by product name, like “Coca” or “Milk”.')
          else if (!_isLoading && _results.isEmpty)
            _HintPanel(
              icon: Icons.search_off,
              text: 'No matches. If you expect products, confirm Xero sync is running and that you have read access to xero_products.',
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _results.length,
                separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, index) {
                  final p = _results[index];
                  return _XeroProductSuggestionTile(
                    product: p,
                    onTap: () => context.pop(p),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _HintPanel extends StatelessWidget {
  final IconData icon;
  final String text;
  const _HintPanel({required this.icon, required this.text});

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

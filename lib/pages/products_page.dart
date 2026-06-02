import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pwa/app_state.dart';
import 'package:pwa/components/app_header.dart';
import 'package:pwa/models/product.dart';
import 'package:pwa/models/xero_product.dart';
import 'package:pwa/nav.dart';
import 'package:pwa/services/xero_product_service.dart';
import 'package:pwa/theme.dart';

class ProductsPage extends StatefulWidget {
  final AppState appState;
  const ProductsPage({super.key, required this.appState});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

enum _ScanChoice { barcode, productName }

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
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _XeroProductNamePickerSheet(initialQuery: _query.trim()),
    );
    if (!mounted || selected == null) return;
    context.push(AppRoutes.xeroProduct(selected.xeroItemId));
  }

  Future<void> _openScanChooser() async {
    final choice = await showModalBottomSheet<_ScanChoice>(
      context: context,
      showDragHandle: true,
      builder: (context) => const _ScanChoiceSheet(),
    );

    if (!mounted || choice == null) return;
    switch (choice) {
      case _ScanChoice.barcode:
        await _openViaBarcode();
      case _ScanChoice.productName:
        await _openViaProductName();
    }
  }

  void _openEditProduct(String id) async {
    final saved = await context.push<bool>(AppRoutes.productEdit(id));
    if (!mounted) return;
    if (saved == true) _showSavedNotification();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.appState.products,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final products = widget.appState.products.products;
        final filtered = products.where((p) {
          if (_query.trim().isEmpty) return true;
          final q = _query.trim().toLowerCase();
          return p.name.toLowerCase().contains(q) || (p.barcode ?? '').toLowerCase().contains(q);
        }).toList();

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
                    child: filtered.isEmpty
                        ? _EmptyState(
                            title: 'Your cart is empty',
                              subtitle: 'Scan or add an item in the search bar above to get started.',
                             onPrimaryAction: _openScanChooser,
                          )
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
                            itemBuilder: (context, index) {
                              final p = filtered[index];
                              return _ProductTile(
                                product: p,
                                onTap: () => _openEditProduct(p.id),
                                onDelete: () async {
                                  final ok = await showModalBottomSheet<bool>(
                                    context: context,
                                    showDragHandle: true,
                                    builder: (context) {
                                      return _ConfirmDeleteSheet(product: p);
                                    },
                                  );
                                  if (ok != true) return;
                                  if (!mounted) return;
                                  await widget.appState.products.deleteById(p.id);

                                  // Force a refresh to reflect server state (and handle
                                  // any RLS-triggered deletes / cascades).
                                  await widget.appState.products.refresh();
                                  if (!mounted) return;
                                  _showDeletedNotification();
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
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
        labelText: 'Search by name or barcode',
        prefixIcon: Icon(Icons.search),
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

class _ProductTile extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ProductTile({required this.product, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final price = (product.priceCents / 100).toStringAsFixed(2);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: AppSpacing.paddingLg,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          color: cs.surface,
          border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(Icons.inventory_2, color: cs.onPrimaryContainer),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name, style: Theme.of(context).textTheme.titleMedium?.semiBold),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Barcode: ${product.barcode ?? '—'} · Stock: ${product.stockQty}',
                    style: Theme.of(context).textTheme.bodySmall?.withColor(cs.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '\$$price',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.semiBold
                      .withColor(cs.primary),
                ),
                const SizedBox(height: AppSpacing.xs),
                IconButton(
                  tooltip: 'Delete',
                  onPressed: onDelete,
                  icon: Icon(Icons.delete_outline, color: cs.error),
                ),
              ],
            ),
          ],
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

class _ConfirmDeleteSheet extends StatelessWidget {
  final Product product;
  const _ConfirmDeleteSheet({required this.product});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: AppSpacing.paddingLg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Delete product?', style: Theme.of(context).textTheme.titleLarge?.semiBold),
          const SizedBox(height: AppSpacing.xs),
          Text(
            product.name,
            style: Theme.of(context).textTheme.bodyMedium?.withColor(cs.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => context.pop(false),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: FilledButton(
                  onPressed: () => context.pop(true),
                  style: FilledButton.styleFrom(backgroundColor: cs.error),
                  child: Text('Delete', style: TextStyle(color: cs.onError)),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
        ],
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

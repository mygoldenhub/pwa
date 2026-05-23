import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pwa/app_state.dart';
import 'package:pwa/components/app_logo.dart';
import 'package:pwa/models/product.dart';
import 'package:pwa/nav.dart';
import 'package:pwa/theme.dart';

class ProductsPage extends StatefulWidget {
  final AppState appState;
  const ProductsPage({super.key, required this.appState});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
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
        context.replace(AppRoutes.products);
      });
    }
  }

  void _openNewProduct() async {
    final saved = await context.push<bool>(AppRoutes.productNew);
    if (!mounted) return;
    if (saved == true) _showSavedNotification();
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
          appBar: AppBar(
            leading: const Padding(
              padding: EdgeInsets.only(left: 12),
              child: Center(child: AppLogo(size: 30, borderRadius: BorderRadius.all(Radius.circular(10)))),
            ),
            leadingWidth: 54,
            title: const Text('Products'),
            actions: [
              IconButton(
                tooltip: 'Add product',
                onPressed: _openNewProduct,
                icon: Icon(Icons.add, color: cs.onSurface),
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
                            title: 'No products yet',
                            subtitle: 'Add your first product to start scanning and selling.',
                            onPrimaryAction: _openNewProduct,
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
                label: Text('Add product', style: TextStyle(color: cs.onPrimary)),
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

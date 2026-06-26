import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pwa/components/app_header.dart';
import 'package:pwa/components/quantity_input.dart';
import 'package:pwa/models/xero_product.dart';
import 'package:pwa/services/cart_service.dart';
import 'package:pwa/services/xero_product_service.dart';
import 'package:pwa/theme.dart';

class XeroProductDetailPage extends StatefulWidget {
  final String xeroItemId;
  const XeroProductDetailPage({super.key, required this.xeroItemId});

  @override
  State<XeroProductDetailPage> createState() => _XeroProductDetailPageState();
}

class _XeroProductDetailPageState extends State<XeroProductDetailPage> {
  late Future<XeroProduct?> _future;
  int _quantity = 1;
  bool _isAdding = false;

  @override
  void initState() {
    super.initState();
    _future = XeroProductService.getByXeroItemId(widget.xeroItemId);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppImpactHeader(
        title: 'Product',
        actions: [
          IconButton(
            tooltip: 'Close',
            onPressed: () => context.pop(),
            icon: Icon(Icons.close, color: cs.onSurface),
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<XeroProduct?>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final p = snap.data;
            if (p == null) {
              debugPrint('XeroProductDetailPage: product not found for ${widget.xeroItemId}');
              return Center(
                child: Padding(
                  padding: AppSpacing.paddingLg,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.search_off, color: cs.onSurfaceVariant, size: 40),
                      const SizedBox(height: AppSpacing.sm),
                      Text('Product not found', style: Theme.of(context).textTheme.titleLarge?.semiBold),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'This item may have been removed from Xero or not synced yet.',
                        style: Theme.of(context).textTheme.bodyMedium?.withColor(cs.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            }

            final priceText = p.salePriceCents == null ? '—' : '\$${(p.salePriceCents! / 100).toStringAsFixed(2)}';
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: SingleChildScrollView(
                  padding: AppSpacing.paddingLg,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadius.xl),
                          color: cs.surface,
                          border: Border.all(color: cs.outline.withValues(alpha: 0.10)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.xl),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Center(
                                child: Container(
                                  width: 112,
                                  height: 112,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(28),
                                    color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
                                  ),
                                  alignment: Alignment.center,
                                  child: Icon(Icons.inventory_2, size: 56, color: cs.onSurfaceVariant),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xl),
                              Text(
                                p.name,
                                style: Theme.of(context).textTheme.titleLarge?.semiBold.copyWith(
                                  fontSize: 30,
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                p.code == null || p.code!.isEmpty ? 'SKU: —' : 'SKU: ${p.code}',
                                style: Theme.of(context).textTheme.titleLarge?.semiBold,
                              ),
                              const SizedBox(height: AppSpacing.xl),
                              Text('Price: $priceText', style: Theme.of(context).textTheme.titleLarge?.semiBold),
                              const SizedBox(height: AppSpacing.xl),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  // Prevent overflow on narrow mobile widths by stacking the label + input.
                                  final isNarrow = constraints.maxWidth < 380;
                                  final label = Text('Quantity', style: Theme.of(context).textTheme.titleLarge?.semiBold);
                                  final input = Align(
                                    alignment: Alignment.centerRight,
                                    child: QuantityInput(
                                      value: _quantity,
                                      min: 1,
                                      max: 9999,
                                      enabled: !_isAdding,
                                      compact: true,
                                      onChanged: (v) => setState(() => _quantity = v),
                                    ),
                                  );

                                  if (isNarrow) {
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        label,
                                        const SizedBox(height: AppSpacing.sm),
                                        input,
                                      ],
                                    );
                                  }

                                  return Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Expanded(child: label),
                                      const SizedBox(width: AppSpacing.md),
                                      Flexible(child: input),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: AppSpacing.xl),

                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: cs.primary, foregroundColor: cs.onPrimary),
                          onPressed: _isAdding
                              ? null
                              : () async {
                                  setState(() => _isAdding = true);
                                  try {
                                     await CartService.addOrIncrementXeroProduct(product: p, quantity: _quantity);
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Added "${p.name}" × $_quantity')),
                                    );
                                    context.pop();
                                  } catch (e) {
                                    debugPrint('XeroProductDetailPage: Add to cart failed: $e');
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Failed to add to cart. Please try again.')),
                                    );
                                  } finally {
                                    if (mounted) setState(() => _isAdding = false);
                                  }
                                },
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 160),
                            child: _isAdding
                                ? SizedBox(
                                    key: const ValueKey('loading'),
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2.5, color: cs.onPrimary),
                                  )
                                : Text(
                                    key: const ValueKey('text'),
                                    'Add to Cart',
                                    style: Theme.of(context).textTheme.titleMedium?.semiBold.withColor(cs.onPrimary),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Center(
                        child: TextButton(
                          onPressed: () => context.pop(),
                          child: Text('Cancel', style: Theme.of(context).textTheme.titleMedium?.semiBold),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ignore: unused_element
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall?.withColor(cs.onSurfaceVariant)),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: Text(value, style: Theme.of(context).textTheme.bodyMedium?.withColor(cs.onSurface))),
      ],
    );
  }
}

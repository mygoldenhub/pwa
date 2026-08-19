import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pwa/components/app_header.dart';
import 'package:pwa/components/quantity_input.dart';
import 'package:pwa/components/xero_product_name_picker.dart';
import 'package:pwa/nav.dart';
import 'package:pwa/models/xero_product.dart';
import 'package:pwa/services/barcode_product_service.dart';
import 'package:pwa/services/cart_service.dart';
import 'package:pwa/services/xero_product_service.dart';
import 'package:pwa/theme.dart';

class _ProductLoadResult {
  final XeroProduct? product;
  final String? barcode;
  final String? message;

  const _ProductLoadResult({
    this.product,
    this.barcode,
    this.message,
  });
}

class XeroProductDetailPage extends StatefulWidget {
  final String xeroItemId;
  final String? barcode;

  const XeroProductDetailPage({
    super.key,
    this.xeroItemId = '',
    this.barcode,
  });

  @override
  State<XeroProductDetailPage> createState() => _XeroProductDetailPageState();
}

class _XeroProductDetailPageState extends State<XeroProductDetailPage> {
  late Future<_ProductLoadResult> _future;
  int _quantity = 1;
  bool _isAdding = false;

  String? get _scannedBarcode {
    final value = widget.barcode?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  bool get _fromBarcode => _scannedBarcode != null;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant XeroProductDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.xeroItemId != widget.xeroItemId || oldWidget.barcode != widget.barcode) {
      _future = _load();
    }
  }

  Future<_ProductLoadResult> _load() async {
    final barcode = _scannedBarcode;
    if (barcode != null) {
      final lookup = await BarcodeProductService.lookup(barcode);
      return _ProductLoadResult(
        product: lookup.product,
        barcode: lookup.barcode,
        message: lookup.ok ? null : lookup.message,
      );
    }

    final p = await XeroProductService.getByXeroItemId(widget.xeroItemId);
    if (p == null) {
      debugPrint('XeroProductDetailPage: product not found for ${widget.xeroItemId}');
      return const _ProductLoadResult(
        message: 'This item may have been removed from Xero or not synced yet.',
      );
    }
    return _ProductLoadResult(product: p);
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/app/cart');
    }
  }

  Future<void> _openManualLookup() async {
    final selected = await showXeroProductNamePicker(context);
    if (!mounted || selected == null) return;
    context.go(AppRoutes.xeroProduct(selected.xeroItemId));
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
            onPressed: _close,
            icon: Icon(Icons.close, color: cs.onSurface),
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<_ProductLoadResult>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return _LookupLoading(barcode: _scannedBarcode);
            }
            final result = snap.data;
            final p = result?.product;
            if (p == null) {
              return _LookupEmpty(
                barcode: result?.barcode ?? _scannedBarcode,
                message: _fromBarcode
                    ? null
                    : (result?.message ?? 'This item may have been removed from Xero or not synced yet.'),
                fromBarcode: _fromBarcode,
                onLookUpProduct: _openManualLookup,
                onScanAgain: () => context.go('/app/cart/scan'),
                onClose: _close,
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
                              if ((result?.barcode ?? '').isNotEmpty) ...[
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  'Barcode: ${result!.barcode}',
                                  style: Theme.of(context).textTheme.bodyMedium?.withColor(cs.onSurfaceVariant),
                                ),
                              ],
                              const SizedBox(height: AppSpacing.xl),
                              Text('Price: $priceText', style: Theme.of(context).textTheme.titleLarge?.semiBold),
                              const SizedBox(height: AppSpacing.xl),
                              LayoutBuilder(
                                builder: (context, constraints) {
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
                                    _close();
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
                          onPressed: _close,
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

class _LookupLoading extends StatelessWidget {
  final String? barcode;
  const _LookupLoading({this.barcode});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: AppSpacing.paddingLg,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 56,
              height: 56,
              child: CircularProgressIndicator(strokeWidth: 3, color: cs.primary),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Looking up product…',
              style: Theme.of(context).textTheme.titleMedium?.semiBold,
              textAlign: TextAlign.center,
            ),
            if ((barcode ?? '').isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                barcode!,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Matching barcode to Xero catalog',
                style: Theme.of(context).textTheme.bodyMedium?.withColor(cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LookupEmpty extends StatelessWidget {
  final String? barcode;
  final String? message;
  final bool fromBarcode;
  final VoidCallback onLookUpProduct;
  final VoidCallback onScanAgain;
  final VoidCallback onClose;

  const _LookupEmpty({
    required this.barcode,
    required this.message,
    required this.fromBarcode,
    required this.onLookUpProduct,
    required this.onScanAgain,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final titleStyle = Theme.of(context).textTheme.titleLarge?.semiBold.copyWith(fontSize: 26);
    final barcodeStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: 24,
          letterSpacing: 1.1,
        );
    final messageStyle = Theme.of(context).textTheme.titleMedium?.withColor(cs.onSurfaceVariant);
    final linkStyle = Theme.of(context).textTheme.titleMedium?.semiBold;

    return Center(
      child: Padding(
        padding: AppSpacing.paddingLg,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off, color: cs.onSurfaceVariant, size: 52),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Product not found',
                style: titleStyle,
                textAlign: TextAlign.center,
              ),
              if ((barcode ?? '').isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  barcode!,
                  style: barcodeStyle,
                  textAlign: TextAlign.center,
                ),
              ],
              if ((message ?? '').isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  message!,
                  style: messageStyle,
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              if (fromBarcode) ...[
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                    ),
                    onPressed: onScanAgain,
                    icon: Icon(Icons.qr_code_scanner, color: cs.onPrimary),
                    label: Text(
                      'Scan again',
                      style: Theme.of(context).textTheme.titleMedium?.semiBold.withColor(cs.onPrimary),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cs.primary,
                    side: BorderSide(color: cs.primary.withValues(alpha: 0.45)),
                  ),
                  onPressed: onLookUpProduct,
                  icon: Icon(Icons.search, color: cs.primary),
                  label: Text(
                    'Look up product',
                    style: Theme.of(context).textTheme.titleMedium?.semiBold.withColor(cs.primary),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: TextButton(
                  onPressed: onClose,
                  child: Text('Back to cart', style: linkStyle),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

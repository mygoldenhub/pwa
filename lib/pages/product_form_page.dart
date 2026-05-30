import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pwa/app_state.dart';
import 'package:pwa/components/app_header.dart';
import 'package:pwa/models/product.dart';
import 'package:pwa/nav.dart';
import 'package:pwa/services/product_service.dart';
import 'package:pwa/theme.dart';

class ProductFormPage extends StatefulWidget {
  final AppState appState;
  final String? productId;
  final String? initialBarcode;
  final String? initialName;

  const ProductFormPage({super.key, required this.appState, required this.productId, this.initialBarcode, this.initialName});

  @override
  State<ProductFormPage> createState() => _ProductFormPageState();
}

class _ProductFormPageState extends State<ProductFormPage> {
  final _nameController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _priceController = TextEditingController();
  final _stockController = TextEditingController();

  Product? _existing;

  @override
  void initState() {
    super.initState();
    _existing = widget.productId == null ? null : widget.appState.products.getById(widget.productId!);
    if (_existing != null) {
      _nameController.text = _existing!.name;
      _barcodeController.text = _existing!.barcode ?? '';
      _priceController.text = (_existing!.priceCents / 100).toStringAsFixed(2);
      _stockController.text = _existing!.stockQty.toString();
    } else {
      _stockController.text = '0';
      final initialBarcode = widget.initialBarcode?.trim();
      if (initialBarcode != null && initialBarcode.isNotEmpty) {
        _barcodeController.text = initialBarcode;
      }

      final initialName = widget.initialName?.trim();
      if (initialName != null && initialName.isNotEmpty) {
        _nameController.text = initialName;
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _barcodeController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    try {
      final name = _nameController.text.trim();
      if (name.isEmpty) throw Exception('Name is required.');

      final barcode = _barcodeController.text.trim();
      final price = double.tryParse(_priceController.text.trim());
      if (price == null || price < 0) throw Exception('Enter a valid price.');

      final stock = int.tryParse(_stockController.text.trim());
      if (stock == null || stock < 0) throw Exception('Enter a valid stock quantity.');

      final now = DateTime.now();
      final product = (_existing ??
              Product(
                id: ProductService.generateUuidV4(),
                name: name,
                barcode: barcode.isEmpty ? null : barcode,
                stockQty: stock,
                priceCents: (price * 100).round(),
                createdAt: now,
                updatedAt: now,
              ))
          .copyWith(
        name: name,
        barcode: barcode.isEmpty ? null : barcode,
        stockQty: stock,
        priceCents: (price * 100).round(),
        updatedAt: now,
      );

      await widget.appState.products.upsert(product);
      if (!mounted) return;

      // Always land on Products after a successful save.
      // We also pass an extra so ProductsPage can show a “saved” snackbar.
      context.go(AppRoutes.cart, extra: const {'product_saved': true});
    } catch (e) {
      debugPrint('Product save failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isEdit = _existing != null;
    final isBusy = widget.appState.products.isLoading;

    return Scaffold(
      appBar: AppImpactHeader(
        title: isEdit ? 'Edit item' : 'New item',
        actions: [
          TextButton(
            onPressed: isBusy ? null : _save,
            child: Text('Save', style: TextStyle(color: cs.primary)),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: AppSpacing.paddingLg,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: AppSpacing.paddingLg,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.xl),
                      color: cs.surface,
                      border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
                    ),
                    child: Column(
                      children: [
                        TextField(
                          controller: _nameController,
                          autofocus: !isEdit,
                          decoration: const InputDecoration(
                            labelText: 'Product name',
                            prefixIcon: Icon(Icons.inventory_2_outlined),
                          ),
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextField(
                          controller: _barcodeController,
                          decoration: const InputDecoration(
                            labelText: 'Barcode (optional)',
                            prefixIcon: Icon(Icons.qr_code),
                          ),
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _priceController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'Price',
                                  prefixIcon: Icon(Icons.attach_money),
                                ),
                                textInputAction: TextInputAction.next,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: TextField(
                                controller: _stockController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Stock qty',
                                  prefixIcon: Icon(Icons.numbers_outlined),
                                ),
                                onSubmitted: (_) => _save(),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: isBusy ? null : _save,
                            icon: Icon(Icons.check, color: cs.onPrimary),
                            label: Text('Save product', style: TextStyle(color: cs.onPrimary)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Tip: later we can wire this to barcode scanning and a real backend.',
                    style: Theme.of(context).textTheme.bodySmall?.withColor(cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

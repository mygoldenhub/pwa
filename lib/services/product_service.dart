import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:pwa/models/product.dart';
import 'package:pwa/supabase/supabase_config.dart';

class ProductService extends ChangeNotifier {
  bool _isInitialized = false;
  bool _isLoading = false;
  bool _productsTableAvailable = true;
  final List<Product> _products = [];

  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;
  List<Product> get products => List.unmodifiable(_products);

  Future<void> init() async {
    if (_isInitialized) return;
    // Scan & Go's live catalog is xero_products. Skip probing public.products so
    // Xero-only Supabase projects don't log a missing-table error on every launch.
    _productsTableAvailable = false;
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> refresh() async {
    if (!_productsTableAvailable) {
      // Xero-only deployments never provision public.products.
      if (_products.isNotEmpty) {
        _products.clear();
        notifyListeners();
      }
      return;
    }
    _isLoading = true;
    notifyListeners();
    try {
      final rows = await SupabaseService.select('products', orderBy: 'updated_at', ascending: false);
      final parsed = <Product>[];
      for (final row in rows) {
        parsed.add(_productFromRow(row));
      }
      _products
        ..clear()
        ..addAll(parsed);
    } catch (e) {
      // Cart / scan use xero_products. Missing public.products is expected.
      if (_looksLikeMissingTableError(e)) {
        _productsTableAvailable = false;
        _products.clear();
        return;
      }
      debugPrint('ProductService.refresh failed: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Product? getById(String id) {
    for (final p in _products) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<void> upsert(Product product) async {
    if (!_productsTableAvailable) return;
    _isLoading = true;
    notifyListeners();
    try {
      final now = DateTime.now().toUtc();
      final isExisting = _products.any((p) => p.id == product.id);
      final payload = {
        'id': product.id,
        'name': product.name,
        'barcode': product.barcode,
        'stock_qty': product.stockQty,
        'price_cents': product.priceCents,
        'updated_at': now.toIso8601String(),
        if (!isExisting) 'created_at': (product.createdAt).toUtc().toIso8601String(),
      };

      await SupabaseService.from('products').upsert(payload);
      await refresh();
    } catch (e) {
      debugPrint('ProductService.upsert failed: $e');
      if (_looksLikeMissingTableError(e)) {
        _productsTableAvailable = false;
        return;
      }
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteById(String id) async {
    if (!_productsTableAvailable) return;
    _isLoading = true;
    notifyListeners();
    try {
      await SupabaseService.delete('products', filters: {'id': id});
      _products.removeWhere((p) => p.id == id);
    } catch (e) {
      debugPrint('ProductService.deleteById failed: $e');
      if (_looksLikeMissingTableError(e)) {
        _productsTableAvailable = false;
        return;
      }
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  bool _looksLikeMissingTableError(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains("could not find the table") ||
        msg.contains('relation "public.products" does not exist') ||
        msg.contains('relation "products" does not exist');
  }

  static String generateUuidV4() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10
    String two(int n) => n.toRadixString(16).padLeft(2, '0');
    final b = bytes.map(two).join();
    return '${b.substring(0, 8)}-${b.substring(8, 12)}-${b.substring(12, 16)}-${b.substring(16, 20)}-${b.substring(20, 32)}';
  }

  Product _productFromRow(Map<String, dynamic> row) {
    final created = DateTime.tryParse(row['created_at']?.toString() ?? '') ?? DateTime.now().toUtc();
    final updated = DateTime.tryParse(row['updated_at']?.toString() ?? '') ?? created;
    return Product(
      id: row['id'].toString(),
      name: row['name'].toString(),
      barcode: row['barcode']?.toString(),
      stockQty: (row['stock_qty'] as num?)?.toInt() ?? 0,
      priceCents: (row['price_cents'] as num?)?.toInt() ?? 0,
      createdAt: created,
      updatedAt: updated,
    );
  }
}

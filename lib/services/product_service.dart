import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:pwa/models/product.dart';
import 'package:pwa/supabase/supabase_config.dart';

class ProductService extends ChangeNotifier {
  bool _isInitialized = false;
  bool _isLoading = false;
  final List<Product> _products = [];

  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;
  List<Product> get products => List.unmodifiable(_products);

  Future<void> init() async {
    if (_isInitialized) return;
    _isLoading = true;
    notifyListeners();
    try {
      await refresh();
    } catch (e) {
      debugPrint('ProductService.init failed: $e');
    } finally {
      _isInitialized = true;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
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
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteById(String id) async {
    _isLoading = true;
    notifyListeners();
    try {
      await SupabaseService.delete('products', filters: {'id': id});
      _products.removeWhere((p) => p.id == id);
    } catch (e) {
      debugPrint('ProductService.deleteById failed: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
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

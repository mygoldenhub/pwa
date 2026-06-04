import 'package:flutter/foundation.dart';
import 'package:pwa/models/cart_item.dart';
import 'package:pwa/models/xero_product.dart';
import 'package:pwa/supabase/supabase_config.dart';

class CartService {
  static const String table = 'cart_items';

  static String _requireUserId() {
    final userId = SupabaseConfig.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      throw 'You must be signed in to use the cart.';
    }
    return userId;
  }

  static Stream<List<CartItem>> streamMyCart() {
    final userId = _requireUserId();
    return SupabaseConfig.client
        .from(table)
        .stream(primaryKey: const ['id'])
        .eq('user_id', userId)
        .order('updated_at', ascending: false)
        .map((rows) => rows.map(CartItem.fromRow).toList());
  }

  /// Adds or updates the item for the current user.
  ///
  /// By default this *sets* the quantity to the chosen amount (not increments).
  static Future<void> upsertXeroProduct({
    required XeroProduct product,
    required int quantity,
  }) async {
    final userId = _requireUserId();
    final q = quantity <= 0 ? 1 : quantity;

    try {
      // Supabase `cart_items.unit_price_cents` is stored as a dollar amount (double).
      // Convert our internal cents representation back into dollars.
      final unitPriceDollars = (product.salePriceCents ?? 0) / 100.0;
      await SupabaseConfig.client.from(table).upsert(
        {
          'user_id': userId,
          'xero_item_id': product.xeroItemId,
          'product_name': product.name,
          'product_code': product.code,
          'unit_price_cents': unitPriceDollars,
          'quantity': q,
        },
        onConflict: 'user_id,xero_item_id',
      );
    } catch (e) {
      debugPrint('CartService.upsertXeroProduct failed: $e');
      rethrow;
    }
  }

  /// Adds an item to the cart.
  ///
  /// - If the product does not exist in the user's cart yet, it inserts a row.
  /// - If it already exists, it increments the existing quantity.
  static Future<void> addOrIncrementXeroProduct({
    required XeroProduct product,
    required int quantity,
  }) async {
    final userId = _requireUserId();
    final addQty = quantity <= 0 ? 1 : quantity;

    try {
      final existing = await SupabaseConfig.client
          .from(table)
          .select('id, quantity')
          .eq('user_id', userId)
          .eq('xero_item_id', product.xeroItemId)
          .maybeSingle();

      // Supabase `cart_items.unit_price_cents` is stored as a dollar amount (double).
      // Convert our internal cents representation back into dollars.
      final unitPriceDollars = (product.salePriceCents ?? 0) / 100.0;

      if (existing == null) {
        await SupabaseConfig.client.from(table).insert({
          'user_id': userId,
          'xero_item_id': product.xeroItemId,
          'product_name': product.name,
          'product_code': product.code,
          'unit_price_cents': unitPriceDollars,
          'quantity': addQty,
        });
        return;
      }

      final existingQty = (existing['quantity'] as num?)?.toInt() ?? 0;
      final newQty = (existingQty + addQty).clamp(1, 9999);
      final cartItemId = existing['id']?.toString();
      if (cartItemId == null || cartItemId.isEmpty) {
        throw 'Cart item id missing for existing row.';
      }

      await SupabaseConfig.client
          .from(table)
          .update({
            'quantity': newQty,
            // Keep the row fresh in case the name/price changed in Xero.
            'product_name': product.name,
            'product_code': product.code,
            'unit_price_cents': unitPriceDollars,
          })
          .eq('id', cartItemId)
          .eq('user_id', userId);
    } catch (e) {
      debugPrint('CartService.addOrIncrementXeroProduct failed: $e');
      rethrow;
    }
  }

  static Future<void> updateQuantity({required String cartItemId, required int quantity}) async {
    final userId = _requireUserId();
    final q = quantity <= 0 ? 1 : quantity;
    try {
      await SupabaseConfig.client.from(table).update({'quantity': q}).eq('id', cartItemId).eq('user_id', userId);
    } catch (e) {
      debugPrint('CartService.updateQuantity failed: $e');
      rethrow;
    }
  }

  static Future<void> deleteItem({required String cartItemId}) async {
    final userId = _requireUserId();
    try {
      await SupabaseConfig.client.from(table).delete().eq('id', cartItemId).eq('user_id', userId);
    } catch (e) {
      debugPrint('CartService.deleteItem failed: $e');
      rethrow;
    }
  }
}

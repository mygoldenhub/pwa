class CartItem {
  final String id;
  final String userId;
  final String xeroItemId;
  final String productName;
  final String? productCode;
  final int? unitPriceCents;
  final int quantity;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CartItem({
    required this.id,
    required this.userId,
    required this.xeroItemId,
    required this.productName,
    required this.productCode,
    required this.unitPriceCents,
    required this.quantity,
    required this.createdAt,
    required this.updatedAt,
  });

  CartItem copyWith({
    String? id,
    String? userId,
    String? xeroItemId,
    String? productName,
    String? productCode,
    int? unitPriceCents,
    int? quantity,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CartItem(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      xeroItemId: xeroItemId ?? this.xeroItemId,
      productName: productName ?? this.productName,
      productCode: productCode ?? this.productCode,
      unitPriceCents: unitPriceCents ?? this.unitPriceCents,
      quantity: quantity ?? this.quantity,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'xero_item_id': xeroItemId,
      'product_name': productName,
      'product_code': productCode,
      'unit_price_cents': unitPriceCents,
      'quantity': quantity,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  static CartItem? fromJson(dynamic json) {
    if (json is! Map) return null;
    final id = json['id']?.toString();
    final userId = json['user_id']?.toString();
    final xeroItemId = json['xero_item_id']?.toString();
    final productName = json['product_name']?.toString();
    final quantityRaw = json['quantity'];
    final createdAtRaw = json['created_at']?.toString();
    final updatedAtRaw = json['updated_at']?.toString();
    if (id == null || userId == null || xeroItemId == null || productName == null) return null;
    if (quantityRaw is! num) return null;
    if (createdAtRaw == null || updatedAtRaw == null) return null;
    final createdAt = DateTime.tryParse(createdAtRaw);
    final updatedAt = DateTime.tryParse(updatedAtRaw);
    if (createdAt == null || updatedAt == null) return null;

    return CartItem(
      id: id,
      userId: userId,
      xeroItemId: xeroItemId,
      productName: productName,
      productCode: json['product_code']?.toString(),
      unitPriceCents: (json['unit_price_cents'] as num?)?.toInt(),
      quantity: quantityRaw.toInt(),
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  static CartItem fromRow(Map<String, dynamic> row) {
    DateTime tryDate(dynamic v) => DateTime.tryParse(v?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);

    // `cart_items.unit_price_cents` is now stored in Supabase as a float/double
    // representing the **dollar** amount (e.g. 91.0 for $91).
    // Internally we keep `unitPriceCents` as integer cents for consistent cart math.
    int? parseUnitPriceCents(dynamic v) {
      if (v == null) return null;
      final n = v as num?;
      if (n == null) return null;
      return (n * 100).round();
    }

    return CartItem(
      id: row['id']?.toString() ?? '',
      userId: row['user_id']?.toString() ?? '',
      xeroItemId: row['xero_item_id']?.toString() ?? '',
      productName: row['product_name']?.toString() ?? '',
      productCode: row['product_code']?.toString(),
      unitPriceCents: parseUnitPriceCents(row['unit_price_cents']),
      quantity: (row['quantity'] as num?)?.toInt() ?? 1,
      createdAt: tryDate(row['created_at']),
      updatedAt: tryDate(row['updated_at']),
    );
  }
}

class Product {
  final String id;
  final String name;
  final String? barcode;
  final int stockQty;
  final int priceCents;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Product({
    required this.id,
    required this.name,
    required this.barcode,
    required this.stockQty,
    required this.priceCents,
    required this.createdAt,
    required this.updatedAt,
  });

  Product copyWith({
    String? id,
    String? name,
    String? barcode,
    int? stockQty,
    int? priceCents,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      barcode: barcode ?? this.barcode,
      stockQty: stockQty ?? this.stockQty,
      priceCents: priceCents ?? this.priceCents,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'barcode': barcode,
      'stockQty': stockQty,
      'priceCents': priceCents,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  static Product? fromJson(dynamic json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    final barcode = json['barcode'];
    final stockQty = json['stockQty'];
    final priceCents = json['priceCents'];
    final createdAt = json['createdAt'];
    final updatedAt = json['updatedAt'];
    if (id is! String || name is! String) return null;
    if (barcode != null && barcode is! String) return null;
    if (stockQty is! int || priceCents is! int) return null;
    if (createdAt is! String || updatedAt is! String) return null;
    final created = DateTime.tryParse(createdAt);
    final updated = DateTime.tryParse(updatedAt);
    if (created == null || updated == null) return null;

    return Product(
      id: id,
      name: name,
      barcode: barcode,
      stockQty: stockQty,
      priceCents: priceCents,
      createdAt: created,
      updatedAt: updated,
    );
  }
}

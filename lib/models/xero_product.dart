class XeroProduct {
  /// Xero ItemID (UUID string)
  final String xeroItemId;
  final String? code;
  final String name;
  final int? salePriceCents;
  final String? salesAccount;
  final String? taxRate;
  final String? description;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const XeroProduct({
    required this.xeroItemId,
    required this.code,
    required this.name,
    required this.salePriceCents,
    required this.salesAccount,
    required this.taxRate,
    required this.description,
    required this.createdAt,
    required this.updatedAt,
  });

  XeroProduct copyWith({
    String? xeroItemId,
    String? code,
    String? name,
    int? salePriceCents,
    String? salesAccount,
    String? taxRate,
    String? description,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return XeroProduct(
      xeroItemId: xeroItemId ?? this.xeroItemId,
      code: code ?? this.code,
      name: name ?? this.name,
      salePriceCents: salePriceCents ?? this.salePriceCents,
      salesAccount: salesAccount ?? this.salesAccount,
      taxRate: taxRate ?? this.taxRate,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'xeroItemId': xeroItemId,
      'code': code,
      'name': name,
      'salePriceCents': salePriceCents,
      'salesAccount': salesAccount,
      'taxRate': taxRate,
      'description': description,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  static XeroProduct? fromJson(dynamic json) {
    if (json is! Map) return null;
    final xeroItemId = json['xeroItemId'];
    final name = json['name'];
    if (xeroItemId is! String || name is! String) return null;
    final createdAtRaw = json['createdAt'];
    final updatedAtRaw = json['updatedAt'];
    return XeroProduct(
      xeroItemId: xeroItemId,
      code: json['code']?.toString(),
      name: name,
      salePriceCents: (json['salePriceCents'] as num?)?.toInt(),
      salesAccount: json['salesAccount']?.toString(),
      taxRate: json['taxRate']?.toString(),
      description: json['description']?.toString(),
      createdAt: createdAtRaw is String ? DateTime.tryParse(createdAtRaw) : null,
      updatedAt: updatedAtRaw is String ? DateTime.tryParse(updatedAtRaw) : null,
    );
  }

  static XeroProduct fromRow(Map<String, dynamic> row) {
    DateTime? tryDate(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());
    return XeroProduct(
      xeroItemId: row['xero_item_id']?.toString() ?? '',
      code: row['code']?.toString(),
      name: row['name']?.toString() ?? '',
      salePriceCents: (row['sale_price_cents'] as num?)?.toInt(),
      salesAccount: row['sales_account']?.toString(),
      taxRate: row['tax_rate']?.toString(),
      description: row['description']?.toString(),
      createdAt: tryDate(row['created_at']),
      updatedAt: tryDate(row['updated_at']),
    );
  }
}

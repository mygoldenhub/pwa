import 'dart:convert';

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

    Map<String, dynamic>? tryJsonMap(dynamic v) {
      if (v == null) return null;
      if (v is Map) return v.cast<String, dynamic>();
      if (v is String) {
        try {
          final decoded = jsonDecode(v);
          if (decoded is Map) return decoded.cast<String, dynamic>();
        } catch (_) {
          return null;
        }
      }
      return null;
    }

    // Old schema: `sale_price_cents` sometimes stored dollars (num), not cents.
    // New schema: sales_details JSON includes UnitPrice.
    int? parseSalePriceCents(dynamic v) {
      if (v == null) return null;
      if (v is num) return (v * 100).round();
      return (num.tryParse(v.toString()) == null) ? null : (num.parse(v.toString()) * 100).round();
    }

    final salesDetails = tryJsonMap(row['sales_details']);
    final unitPrice = salesDetails?['UnitPrice'] ?? salesDetails?['unit_price'] ?? salesDetails?['unitPrice'];

    return XeroProduct(
      xeroItemId: row['item_id']?.toString() ?? row['xero_item_id']?.toString() ?? '',
      code: row['code']?.toString(),
      name: row['name']?.toString() ?? '',
      salePriceCents: parseSalePriceCents(unitPrice ?? row['sale_price_cents']),
      salesAccount: (salesDetails?['AccountCode'] ?? salesDetails?['account_code'] ?? row['sales_account'])?.toString(),
      taxRate: (salesDetails?['TaxType'] ?? salesDetails?['tax_type'] ?? row['tax_rate'])?.toString(),
      description: row['description']?.toString(),
      createdAt: tryDate(row['created_at']),
      updatedAt: tryDate(row['updated_date_utc'] ?? row['updated_at']),
    );
  }
}

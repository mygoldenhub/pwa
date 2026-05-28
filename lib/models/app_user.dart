class AppUser {
  final String id;
  final String email;
  final String displayName;
  final String? companyName;
  final String? phoneNumber;
  final String? xeroAccountId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AppUser({
    required this.id,
    required this.email,
    required this.displayName,
    this.companyName,
    this.phoneNumber,
    this.xeroAccountId,
    required this.createdAt,
    required this.updatedAt,
  });

  AppUser copyWith({
    String? id,
    String? email,
    String? displayName,
    String? companyName,
    String? phoneNumber,
    String? xeroAccountId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AppUser(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      companyName: companyName ?? this.companyName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      xeroAccountId: xeroAccountId ?? this.xeroAccountId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'displayName': displayName,
      'companyName': companyName,
      'phoneNumber': phoneNumber,
      'xeroAccountId': xeroAccountId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  static AppUser? fromJson(dynamic json) {
    if (json is! Map) return null;
    final id = json['id'];
    final email = json['email'];
    final displayName = json['displayName'];
    final companyName = json['companyName'];
    final phoneNumber = json['phoneNumber'];
    final xeroAccountId = json['xeroAccountId'];
    final createdAt = json['createdAt'];
    final updatedAt = json['updatedAt'];
    if (id is! String || email is! String || displayName is! String) return null;
    if (createdAt is! String || updatedAt is! String) return null;

    final created = DateTime.tryParse(createdAt);
    final updated = DateTime.tryParse(updatedAt);
    if (created == null || updated == null) return null;

    return AppUser(
      id: id,
      email: email,
      displayName: displayName,
      companyName: companyName is String ? companyName : null,
      phoneNumber: phoneNumber is String ? phoneNumber : null,
      xeroAccountId: xeroAccountId is String ? xeroAccountId : null,
      createdAt: created,
      updatedAt: updated,
    );
  }
}

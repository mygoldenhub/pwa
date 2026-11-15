class AppUser {
  final String id;
  final String email;
  final String displayName;
  final String? companyName;
  final String? phoneNumber;
  final String? xeroAccountId;
  /// `0` is a regular user. `1` is an admin.
  final int role;
  /// `1` may log in. `0` is waiting for (or was denied) admin approval.
  final int status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AppUser({
    required this.id,
    required this.email,
    required this.displayName,
    this.companyName,
    this.phoneNumber,
    this.xeroAccountId,
    this.role = 0,
    this.status = 1,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isAdmin => role == 1;

  /// Only status 1 may log in — admins included. Anything else is blocked.
  bool get isPendingApproval => status != 1;

  AppUser copyWith({
    String? id,
    String? email,
    String? displayName,
    String? companyName,
    String? phoneNumber,
    String? xeroAccountId,
    int? role,
    int? status,
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
      role: role ?? this.role,
      status: status ?? this.status,
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
      'role': role,
      'status': status,
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
    final roleRaw = json['role'];
    final statusRaw = json['status'];
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
      role: roleRaw is int ? roleRaw : (roleRaw is num ? roleRaw.toInt() : int.tryParse('$roleRaw') ?? 0),
      status: statusRaw is num ? statusRaw.toInt() : (int.tryParse('${statusRaw ?? ''}') ?? 1),
      createdAt: created,
      updatedAt: updated,
    );
  }
}

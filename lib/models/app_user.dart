class AppUser {
  final String id;
  final String email;
  final String displayName;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AppUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.createdAt,
    required this.updatedAt,
  });

  AppUser copyWith({
    String? id,
    String? email,
    String? displayName,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AppUser(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'displayName': displayName,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  static AppUser? fromJson(dynamic json) {
    if (json is! Map) return null;
    final id = json['id'];
    final email = json['email'];
    final displayName = json['displayName'];
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
      createdAt: created,
      updatedAt: updated,
    );
  }
}

class AuthSession {
  final String? token; // present on register/login/guest, not on /me
  final int userId;
  final String username;
  final int? storeId;
  final int? defaultStoreId; // system-configured fallback store
  final String? mode; // NORMAL | KIOSK | SHOPPING
  final Map<String, String>? properties; // system properties map
  final Set<String> permissions; // resolved permission names for current store

  const AuthSession({
    this.token,
    required this.userId,
    required this.username,
    this.storeId,
    this.defaultStoreId,
    this.mode,
    this.properties,
    this.permissions = const {},
  });

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final rawProps = json['properties'];
    Map<String, String>? properties;
    if (rawProps is Map) {
      properties = rawProps.map((k, v) => MapEntry(k.toString(), v.toString()));
    }
    final rawPerms = json['permissions'];
    final Set<String> permissions = rawPerms is List
        ? rawPerms.map((e) => e.toString()).toSet()
        : const {};
    return AuthSession(
      token: json['token'] as String?,
      userId: json['userId'] as int,
      username: json['username'] as String,
      storeId: json['storeId'] as int?,
      defaultStoreId: json['defaultStoreId'] as int?,
      mode: json['mode'] as String?,
      properties: properties,
      permissions: permissions,
    );
  }
}

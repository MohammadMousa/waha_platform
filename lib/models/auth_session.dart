class AuthSession {
  final String? token; // present on register/login/guest, not on /me
  final int? userId; // absent on a Kiosk device session (see deviceId)
  final int? deviceId; // present only on a Kiosk device session
  final String? username; // absent on device/employee login responses —
  // those identify by id, not username; callers pass usernameOverride.
  final int? storeId;
  final int? defaultStoreId; // system-configured fallback store
  final String? mode; // NORMAL | KIOSK | SHOPPING
  final Map<String, String>? properties; // system properties map
  final Set<String> permissions; // resolved permission names for current store

  const AuthSession({
    this.token,
    this.userId,
    this.deviceId,
    this.username,
    this.storeId,
    this.defaultStoreId,
    this.mode,
    this.properties,
    this.permissions = const {},
  });

  /// [usernameOverride] fills in `username` when the backend response
  /// doesn't carry one — the Kiosk device login response identifies by
  /// `deviceId`, not username (see docs/roles-permissions.md), so the
  /// caller passes back the username it just logged in with.
  factory AuthSession.fromJson(Map<String, dynamic> json, {String? usernameOverride}) {
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
      userId: json['userId'] as int?,
      deviceId: json['deviceId'] as int?,
      username: (json['username'] as String?) ?? usernameOverride,
      storeId: json['storeId'] as int?,
      defaultStoreId: json['defaultStoreId'] as int?,
      mode: json['mode'] as String?,
      properties: properties,
      permissions: permissions,
    );
  }
}

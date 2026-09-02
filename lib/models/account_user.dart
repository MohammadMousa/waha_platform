class AccountUser {
  final int id;
  final String username;
  final String accountType;
  final bool enabled;
  final String? firstName;
  final String? lastName;
  final String? phone;
  final String? roleName;
  final int? storeId;
  final String? storeName;
  final String? createdAt;
  final String? lastLoginAt;

  const AccountUser({
    required this.id,
    required this.username,
    required this.accountType,
    required this.enabled,
    this.firstName,
    this.lastName,
    this.phone,
    this.roleName,
    this.storeId,
    this.storeName,
    this.createdAt,
    this.lastLoginAt,
  });

  factory AccountUser.fromJson(Map<String, dynamic> j) => AccountUser(
        id: (j['id'] as num).toInt(),
        username: j['username'] as String,
        accountType: j['accountType'] as String? ?? 'HUMAN',
        enabled: j['enabled'] as bool? ?? true,
        firstName: j['firstName'] as String?,
        lastName: j['lastName'] as String?,
        phone: j['phone'] as String?,
        roleName: j['roleName'] as String?,
        storeId: j['storeId'] == null ? null : (j['storeId'] as num).toInt(),
        storeName: j['storeName'] as String?,
        createdAt: j['createdAt'] as String?,
        lastLoginAt: j['lastLoginAt'] as String?,
      );

  String get displayName {
    final parts = [firstName, lastName].where((s) => s != null && s.isNotEmpty).toList();
    return parts.isNotEmpty ? parts.join(' ') : username;
  }

  String get initials {
    if (firstName != null && firstName!.isNotEmpty) return firstName![0].toUpperCase();
    return username.isNotEmpty ? username[0].toUpperCase() : '?';
  }
}

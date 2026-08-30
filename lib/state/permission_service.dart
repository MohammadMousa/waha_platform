import 'package:flutter/material.dart';

/// Caches resolved permissions for the current user+store context.
/// Updated on every login, guest session, store switch, and /me refresh.
/// On 403 response, the caller should call clear() then re-fetch /me.
///
/// Permission checks here are UX only (hide controls, skip pointless calls).
/// The backend always re-enforces — a bypassed check results in a 403, not a breach.
/// Usage: permissionService.can('EDIT_PRODUCTS')
class PermissionService extends ChangeNotifier {
  Set<String> _permissions = {};

  bool can(String permission) => _permissions.contains(permission);

  bool get canEditAnything =>
      _permissions.any({'EDIT_PRODUCTS', 'MANAGE_CATEGORIES', 'MANAGE_STORES'}.contains);

  void update(Set<String> permissions) {
    _permissions = permissions;
    notifyListeners();
  }

  void clear() {
    _permissions = {};
    notifyListeners();
  }
}

final permissionService = PermissionService();

import 'package:flutter/material.dart';

import '../services/local_prefs.dart';

/// Per-device store binding and system app config (app name from server properties).
/// storeId null = not configured yet; never use 0 as a sentinel here.
///
/// storeName, storeCurrency, and appName are in-memory only — always
/// re-resolved at runtime via resolveDefaultStore / _applySession.
class StoreConfigService extends ChangeNotifier {
  int? _storeId;
  String? _storeName;
  String? _storeCurrency;
  Map<String, dynamic>? _appName; // {"en": "Waha", "ar": "واحة"}

  StoreConfigService(this._storeId);

  int? get storeId => _storeId;
  String? get storeName => _storeName;
  String? get storeCurrency => _storeCurrency;
  Map<String, dynamic>? get appName => _appName;

  void setStoreId(int id, {bool persist = true}) {
    if (_storeId == id) return;
    _storeId = id;
    if (persist) LocalPrefs.setStoreId(id);
    notifyListeners();
  }

  void setStore(int id, {String? name, String? currency, bool persist = true}) {
    _storeId = id;
    _storeName = name;
    _storeCurrency = currency;
    if (persist) LocalPrefs.setStoreId(id);
    notifyListeners();
  }

  /// Updates the active store in-memory only — never writes to LocalPrefs.
  /// Use this for session switches and startup resolution; only "Make Default"
  /// in the store picker should ever write to LocalPrefs.
  void applySessionStore(int id, {String? name, String? currency}) {
    _storeId = id;
    if (name != null) _storeName = name;
    if (currency != null) _storeCurrency = currency;
    notifyListeners();
  }

  void setAppName(Map<String, dynamic> nameMap) {
    _appName = nameMap;
    notifyListeners();
  }
}

const _dartDefineStoreId = int.fromEnvironment('STORE_ID', defaultValue: 0);

final storeConfigService =
    StoreConfigService(_dartDefineStoreId == 0 ? null : _dartDefineStoreId);

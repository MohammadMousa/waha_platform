import 'dart:math';

import 'package:flutter/foundation.dart';

import '../services/local_prefs.dart';

enum SimScanType { product }

class SimulatorService extends ChangeNotifier {
  bool _enabled = true;
  bool _clusterVisible;
  bool _devToolsHidden;
  final Map<SimScanType, List<String>> _cachedCodes = {
    SimScanType.product: [],
  };

  SimulatorService()
      : _devToolsHidden = !LocalPrefs.simDevToolsVisible,
        _clusterVisible = LocalPrefs.simDevToolsVisible {
    _cachedCodes[SimScanType.product] = List.of(LocalPrefs.simProductCodes);
  }

  bool get enabled => _enabled;
  bool get clusterVisible => _enabled && _clusterVisible && !_devToolsHidden;
  bool get devToolsHidden => _devToolsHidden;

  // Returns a random code from the saved list, or null if the list is empty.
  String? cachedCode(SimScanType type) {
    final list = _cachedCodes[type] ?? [];
    if (list.isEmpty) return null;
    if (list.length == 1) return list[0];
    return list[Random().nextInt(list.length)];
  }

  // Returns all saved codes — used by the settings screen to populate fields.
  List<String> cachedCodes(SimScanType type) =>
      List.unmodifiable(_cachedCodes[type] ?? []);

  // Replaces the full list and persists it.
  void setCachedCodes(SimScanType type, List<String> codes) {
    _cachedCodes[type] = List.of(codes);
    if (type == SimScanType.product) LocalPrefs.setSimProductCodes(codes);
    notifyListeners();
  }

  // Quick one-off set from the long-press dialog — replaces the list with the
  // single entered code rather than appending, keeping the overlay behaviour
  // identical to before the multi-code feature was added.
  void setCachedCode(SimScanType type, String code) {
    setCachedCodes(type, code.isEmpty ? [] : [code]);
  }

  // Adds a newly entered code to the saved list instead of replacing it, so
  // every code entered via the long-press dialog stays available for
  // cachedCode's random pick, rather than the latest entry wiping the rest.
  void addCachedCode(SimScanType type, String code) {
    if (code.isEmpty) return;
    final list = List<String>.of(_cachedCodes[type] ?? <String>[]);
    if (!list.contains(code)) list.add(code);
    setCachedCodes(type, list);
  }

  void setEnabled(bool value) {
    _enabled = value;
    notifyListeners();
  }

  void hideCluster() {
    _clusterVisible = false;
    notifyListeners();
  }

  void showCluster() {
    _clusterVisible = true;
    notifyListeners();
  }

  void hideDevTools() {
    _devToolsHidden = true;
    _clusterVisible = false;
    LocalPrefs.setSimDevToolsVisible(false);
    notifyListeners();
  }

  void showDevTools() {
    _devToolsHidden = false;
    _clusterVisible = true;
    LocalPrefs.setSimDevToolsVisible(true);
    notifyListeners();
  }
}

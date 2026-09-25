import 'dart:math';

import 'package:flutter/foundation.dart';

import '../services/local_prefs.dart';

enum SimScanType { product }

/// Shortcut buttons in the simulator cluster whose visibility is
/// configurable — Close and "hide dev tools" are the panel's own meta
/// controls and are never optional. 'browse' opens the Products/Browse
/// screen — named to match Routes.browse and the bottom nav's own label.
/// 'sessionInfo' toggles the session-info footer strip (see showFooter
/// below) — it doesn't navigate anywhere, tapping it just shows/hides text.
enum SimPinnedButton {
  home,
  settings,
  camera,
  productScan,
  browse,
  sessionInfo
}

/// Ships with 'home' and 'productScan' (manual barcode entry) OFF — the
/// common case doesn't need either pinned, and a cluttered cluster is worse
/// than one extra trip through Settings to turn a button back on.
/// 'sessionInfo' is pinned by default, per explicit request.
const _defaultPinnedButtons = {
  SimPinnedButton.settings,
  SimPinnedButton.camera,
  SimPinnedButton.browse,
  SimPinnedButton.sessionInfo,
};

class SimulatorService extends ChangeNotifier {
  bool _enabled = true;
  bool _clusterVisible;
  bool _devToolsHidden;
  bool _autoCache;
  int _cacheLimit;
  bool _showFooter;
  final Set<SimPinnedButton> _pinnedButtons;
  final Map<SimScanType, List<String>> _cachedCodes = {
    SimScanType.product: [],
  };

  SimulatorService()
      : _devToolsHidden = !LocalPrefs.simDevToolsVisible,
        _clusterVisible = LocalPrefs.simDevToolsVisible,
        _autoCache = LocalPrefs.simAutoCache,
        _cacheLimit = LocalPrefs.simCacheLimit,
        _showFooter = LocalPrefs.showSessionFooter,
        _pinnedButtons = _decodePinnedButtons(LocalPrefs.simPinnedButtons) {
    _cachedCodes[SimScanType.product] = List.of(LocalPrefs.simProductCodes);
  }

  static Set<SimPinnedButton> _decodePinnedButtons(List<String>? saved) {
    if (saved == null) return Set.of(_defaultPinnedButtons);
    return saved
        .map((name) =>
            SimPinnedButton.values.where((b) => b.name == name).firstOrNull)
        .whereType<SimPinnedButton>()
        .toSet();
  }

  bool get enabled => _enabled;
  bool get clusterVisible => _enabled && _clusterVisible && !_devToolsHidden;
  bool get devToolsHidden => _devToolsHidden;
  bool get autoCache => _autoCache;
  int get cacheLimit => _cacheLimit;
  bool get showFooter => _showFooter;

  bool isPinned(SimPinnedButton button) => _pinnedButtons.contains(button);

  void setPinned(SimPinnedButton button, bool value) {
    if (value) {
      _pinnedButtons.add(button);
    } else {
      _pinnedButtons.remove(button);
    }
    LocalPrefs.setSimPinnedButtons(_pinnedButtons.map((b) => b.name).toList());
    notifyListeners();
  }

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

  // Auto-cache hook: called after every simulator-fired scan (tap,
  // long-press manual entry, camera-via-simulator) when autoCache is on.
  // No-ops when autoCache is off, the code is empty, already present, or
  // the list has already reached cacheLimit — full just means full, new
  // entries are silently dropped rather than evicting older ones.
  void tryAutoCache(SimScanType type, String code) {
    if (!_autoCache || code.isEmpty) return;
    final list = _cachedCodes[type] ?? const <String>[];
    if (list.contains(code) || list.length >= _cacheLimit) return;
    addCachedCode(type, code);
  }

  void setAutoCache(bool value) {
    _autoCache = value;
    LocalPrefs.setSimAutoCache(value);
    notifyListeners();
  }

  void setCacheLimit(int value) {
    _cacheLimit = value;
    LocalPrefs.setSimCacheLimit(value);
    notifyListeners();
  }

  // The session-info footer's own visibility. Two distinct, deliberately
  // separate mechanisms:
  //  - toggleFooter(): the cluster's sessionInfo button AND tapping the
  //    footer strip itself — a live, in-session flip only, never written to
  //    LocalPrefs. Doesn't survive a restart on its own.
  //  - saveFooterVisibility(): the ONLY thing that persists
  //    (LocalPrefs.showSessionFooter) so it survives a restart — called
  //    from a real "Save" action in Simulator Settings, not on every toggle.
  void toggleFooter() {
    _showFooter = !_showFooter;
    notifyListeners();
  }

  void saveFooterVisibility(bool value) {
    _showFooter = value;
    LocalPrefs.setShowSessionFooter(value);
    notifyListeners();
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

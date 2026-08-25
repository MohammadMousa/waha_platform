import 'package:flutter/foundation.dart';

import '../services/local_prefs.dart';

/// Scan types the simulator knows about. Only [product] is wired to
/// anything right now — coupon/wallet aren't in the backend contract yet,
/// so they intentionally have no button and no cached-value slot. Adding
/// one later means adding an enum case + a settings field, reusing the
/// same click/long-press mechanism everywhere else.
enum SimScanType { product }

/// Holds the cached code-per-type and the enabled/visible state for the
/// floating simulator cluster.
/// Visibility persists across restarts via LocalPrefs — if the user explicitly
/// showed dev tools, they stay shown on next boot. Default is hidden.
class SimulatorService extends ChangeNotifier {
  bool _enabled = true;
  bool _clusterVisible;
  bool _devToolsHidden;
  final Map<SimScanType, String?> _cachedCodes = {
    SimScanType.product: null,
  };

  SimulatorService()
      : _devToolsHidden = !LocalPrefs.simDevToolsVisible,
        _clusterVisible = LocalPrefs.simDevToolsVisible;

  bool get enabled => _enabled;
  bool get clusterVisible => _enabled && _clusterVisible && !_devToolsHidden;
  bool get devToolsHidden => _devToolsHidden;

  String? cachedCode(SimScanType type) => _cachedCodes[type];

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

  /// Completely hides the simulator cluster, the reopen chip, and the mode
  /// badge. Intended for kiosk demonstrations. Secret gesture (5 taps on
  /// the mode badge position) reveals everything again via [showDevTools].
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

  void setCachedCode(SimScanType type, String code) {
    _cachedCodes[type] = code;
    notifyListeners();
  }
}

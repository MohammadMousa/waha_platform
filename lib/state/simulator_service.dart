import 'package:flutter/foundation.dart';

/// Scan types the simulator knows about. Only [product] is wired to
/// anything right now — coupon/wallet aren't in the backend contract yet,
/// so they intentionally have no button and no cached-value slot. Adding
/// one later means adding an enum case + a settings field, reusing the
/// same click/long-press mechanism everywhere else.
enum SimScanType { product }

/// Holds the cached code-per-type and the enabled/visible state for the
/// floating simulator cluster. Deliberately in-memory only — this is a
/// dev tool, not something that needs to survive an app restart.
class SimulatorService extends ChangeNotifier {
  bool _enabled = true;
  bool _clusterVisible = true;
  final Map<SimScanType, String?> _cachedCodes = {
    SimScanType.product: null,
  };

  bool get enabled => _enabled;
  bool get clusterVisible => _enabled && _clusterVisible;

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

  void setCachedCode(SimScanType type, String code) {
    _cachedCodes[type] = code;
    notifyListeners();
  }
}

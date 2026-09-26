import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';

import '../services/local_prefs.dart';

/// The reference machines the UI is designed for, in logical pixels
/// (width x height, portrait). Same numbers as the company's desktop
/// emulator list. A physical kiosk screen is far denser in pixels than a
/// phone, so its controls look tiny unless the whole UI is scaled up until the
/// screen matches one of these.
enum ScreenMachine {
  mobile('Mobile', 405, 814),
  smallKiosk('Small kiosk', 491, 756),
  largeKiosk('Large kiosk', 491, 873);

  final String label;
  final double designWidth;
  final double designHeight;
  const ScreenMachine(this.label, this.designWidth, this.designHeight);
}

enum ScreenFactorMode { auto, manual }

/// Screens narrower than this (shortest side, logical px) are phones: never
/// scaled in Auto, so they look exactly as before.
const double kMobileMaxShortSide = 600;

/// Short-side / long-side at or above this is a small kiosk (0.65), below it a
/// large kiosk (0.56).
const double kSmallKioskMinRatio = 0.605;

const double kMinScreenScale = 0.5;
const double kMaxScreenScale = 3.0;

/// Which machine an unknown screen is closest to.
ScreenMachine classifyScreen(Size logical) {
  final short = math.min(logical.width, logical.height);
  final long = math.max(logical.width, logical.height);
  if (short < kMobileMaxShortSide) return ScreenMachine.mobile;
  return short / long >= kSmallKioskMinRatio
      ? ScreenMachine.smallKiosk
      : ScreenMachine.largeKiosk;
}

/// How much to enlarge the UI so [logical] looks like [machine]: the smaller of
/// (short side / design width) and (long side / design height), so nothing is
/// cut off in either direction.
double scaleForMachine(Size logical, ScreenMachine machine) {
  final short = math.min(logical.width, logical.height);
  final long = math.max(logical.width, logical.height);
  final s = math.min(short / machine.designWidth, long / machine.designHeight);
  return s.clamp(kMinScreenScale, kMaxScreenScale).toDouble();
}

/// Auto: phones stay at exactly 1.0; bigger screens go to their machine.
/// Manual: [manual] machine, whatever the screen is.
double screenScale(Size logical,
    {required ScreenFactorMode mode, required ScreenMachine manual}) {
  if (mode == ScreenFactorMode.manual) return scaleForMachine(logical, manual);
  final m = classifyScreen(logical);
  return m == ScreenMachine.mobile ? 1.0 : scaleForMachine(logical, m);
}

/// The Settings choice, saved on the device. Listeners rebuild the app live.
class ScreenFactorSettings extends ChangeNotifier {
  ScreenFactorMode get mode => LocalPrefs.screenFactorMode == 'manual'
      ? ScreenFactorMode.manual
      : ScreenFactorMode.auto;

  ScreenMachine get manualMachine => ScreenMachine.values.firstWhere(
        (m) => m.name == LocalPrefs.screenFactorMachine,
        orElse: () => ScreenMachine.largeKiosk,
      );

  Future<void> setAuto() async {
    await LocalPrefs.setScreenFactorMode('auto');
    notifyListeners();
  }

  Future<void> setManual(ScreenMachine machine) async {
    await LocalPrefs.setScreenFactorMachine(machine.name);
    await LocalPrefs.setScreenFactorMode('manual');
    notifyListeners();
  }

  double scaleFor(Size logical) =>
      screenScale(logical, mode: mode, manual: manualMachine);
}

final screenFactor = ScreenFactorSettings();

import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:waha_kiosk/config/screen_factor.dart';

void main() {
  test('phones are Mobile and never scaled in Auto', () {
    const a32 = Size(411, 914); // 1080x2400 @ 2.625
    expect(classifyScreen(a32), ScreenMachine.mobile);
    expect(
        screenScale(a32, mode: ScreenFactorMode.auto, manual: ScreenMachine.largeKiosk),
        1.0);
  });

  test('a 1080x1920 kiosk at density 1 is a Large kiosk, scaled ~2.2x', () {
    const big = Size(1080, 1920);
    expect(classifyScreen(big), ScreenMachine.largeKiosk);
    expect(scaleForMachine(big, ScreenMachine.largeKiosk),
        closeTo(1080 / 491, 0.01));
  });

  test('a squarer kiosk screen is a Small kiosk', () {
    const small = Size(800, 1230); // ratio 0.65
    expect(classifyScreen(small), ScreenMachine.smallKiosk);
  });

  test('landscape is treated like portrait', () {
    expect(classifyScreen(const Size(1920, 1080)), ScreenMachine.largeKiosk);
  });

  test('manual mode forces the chosen machine, even on a phone', () {
    const a32 = Size(411, 914);
    final s = screenScale(a32,
        mode: ScreenFactorMode.manual, manual: ScreenMachine.largeKiosk);
    expect(s, closeTo(411 / 491, 0.01)); // shrinks to look like a kiosk layout
  });

  test('scale is clamped', () {
    expect(scaleForMachine(const Size(5000, 9000), ScreenMachine.mobile),
        kMaxScreenScale);
  });
}

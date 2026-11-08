import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:waha_kiosk/services/api_client.dart';
import 'package:waha_kiosk/state/order_flow_controller.dart';
import 'package:waha_kiosk/utils/scanner_manager.dart';

void main() {
  Future<BuildContext> pumpContext(WidgetTester tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => OrderFlowController(ApiClient(baseUrl: 'http://127.0.0.1:1')),
      child: MaterialApp(
        home: Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        }),
      ),
    ));
    return ctx;
  }

  testWidgets('a product barcode is not a command', (tester) async {
    final ctx = await pumpContext(tester);
    expect(await ScannerManager.instance.handle(ctx, '6281000123456'), isFalse);
  });

  testWidgets('an unknown cmd= code is swallowed, not treated as a barcode',
      (tester) async {
    final ctx = await pumpContext(tester);
    expect(await ScannerManager.instance.handle(ctx, 'cmd=nothing-here'), isTrue);
  });

  // Every scan path must make the ONE ScannerManager.handle call. A scan rule
  // placed anywhere else is skipped by the paths that lack it (the simulator
  // once missed coupons that way). This fails if a path stops calling it.
  test('camera, hardware and simulator scans all go through handle()', () {
    for (final f in [
      'lib/utils/scan_actions.dart',
      'lib/widgets/simulator_overlay.dart',
    ]) {
      expect(File(f).readAsStringSync(),
          contains('ScannerManager.instance.handle('),
          reason: '$f must call ScannerManager.instance.handle');
    }
  });
}

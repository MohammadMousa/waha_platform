import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waha_kiosk/utils/scanner_manager.dart';

void main() {
  Future<BuildContext> pumpContext(WidgetTester tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }),
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
}

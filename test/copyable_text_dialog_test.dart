import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waha_kiosk/screens/settings_screen.dart' show showCopyableTextDialog;

/// The dialog behind Settings' "Session info" and the cmd=build-info scan:
/// Close button, a tap outside closes it, and with autoClose it goes by itself.
void main() {
  Future<BuildContext> pumpHost(WidgetTester tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        ctx = c;
        return const Scaffold(body: Text('page'));
      }),
    ));
    return ctx;
  }

  testWidgets('closes by itself after the time', (tester) async {
    final ctx = await pumpHost(tester);
    showCopyableTextDialog(ctx, 'Info', 'abc',
        autoClose: const Duration(seconds: 60));
    await tester.pumpAndSettle();
    expect(find.text('Info'), findsOneWidget);
    await tester.pump(const Duration(seconds: 59));
    expect(find.text('Info'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Info'), findsNothing);
  });

  testWidgets('the Close button and a tap outside both close it', (tester) async {
    final ctx = await pumpHost(tester);
    showCopyableTextDialog(ctx, 'Info', 'abc');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Info'), findsNothing);

    showCopyableTextDialog(ctx, 'Info', 'abc');
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5)); // the barrier, outside the dialog
    await tester.pumpAndSettle();
    expect(find.text('Info'), findsNothing);
  });

  testWidgets('closed by hand first: the timer does not pop the page underneath',
      (tester) async {
    final ctx = await pumpHost(tester);
    showCopyableTextDialog(ctx, 'Info', 'abc',
        autoClose: const Duration(seconds: 60));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 120));
    expect(find.text('page'), findsOneWidget);
  });
}

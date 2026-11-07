import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:waha_kiosk/data/sync/run_result.dart';
import 'package:waha_kiosk/l10n/generated/app_localizations.dart';
import 'package:waha_kiosk/widgets/run_result_text.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final ar = lookupAppLocalizations(const Locale('ar'));

  test('every pull ending has a message in both languages', () {
    for (final k in RunKind.values) {
      final r = RunResult(k, count: 3, detail: 'x', waitSeconds: 30);
      expect(pullResultText(en, r), isNotEmpty);
      expect(pullResultText(ar, r), isNotEmpty);
      expect(pullResultText(ar, r), isNot(pullResultText(en, r)));
    }
    expect(pullResultText(en, const RunResult(RunKind.done, count: 12)),
        'Pull finished: 12 rows updated');
  });

  test('send messages say what happened', () {
    expect(sendResultText(en, const RunResult(RunKind.done)),
        'Nothing is waiting to send');
    expect(sendResultText(en, const RunResult(RunKind.done, count: 2)),
        'Sent 2 order(s) to the server');
    expect(
        sendResultText(
            en, const RunResult(RunKind.done, count: 1, rejected: 1)),
        contains('rejected 1'));
    expect(sendResultText(ar, const RunResult(RunKind.noSession)), isNotEmpty);
    expect(isProblem(const RunResult(RunKind.failed)), isTrue);
    expect(isProblem(const RunResult(RunKind.done, count: 1)), isFalse);
  });
}

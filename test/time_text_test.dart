import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waha_kiosk/l10n/generated/app_localizations.dart';
import 'package:waha_kiosk/utils/time_text.dart';

void main() {
  final now = DateTime(2026, 11, 7, 15, 41, 0);
  final en = lookupAppLocalizations(const Locale('en'));
  final ar = lookupAppLocalizations(const Locale('ar'));

  test('ago shows the two largest units', () {
    expect(agoText(en, now.subtract(const Duration(seconds: 2)), now: now), 'just now');
    expect(agoText(en, now.subtract(const Duration(seconds: 35)), now: now), '35s ago');
    expect(agoText(en, now.subtract(const Duration(minutes: 4, seconds: 10)), now: now), '4m 10s ago');
    expect(agoText(en, now.subtract(const Duration(hours: 4, minutes: 10)), now: now), '4h 10m ago');
    expect(agoText(en, now.subtract(const Duration(days: 2, hours: 3, minutes: 5)), now: now), '2d 3h ago');
  });

  test('12-hour clock, date only when not today, Arabic suffix', () {
    expect(clock12(en, DateTime(2026, 11, 7, 15, 5), now: now), '3:05 PM');
    expect(clock12(en, DateTime(2026, 11, 7, 0, 5), now: now), '12:05 AM');
    expect(clock12(en, DateTime(2026, 11, 5, 9, 30), now: now), '05 Nov 9:30 AM');
    expect(clock12(ar, DateTime(2026, 11, 7, 15, 5), now: now), '3:05 م');
  });

  test('missing time is a dash; arabic ago reads منذ', () {
    expect(whenText(en, null), '-');
    expect(agoText(ar, now.subtract(const Duration(hours: 1, minutes: 2)), now: now),
        startsWith('منذ'));
  });
}

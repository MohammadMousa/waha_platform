import 'package:flutter_test/flutter_test.dart';
import 'package:waha_kiosk/data/sync/table_freshness.dart';

/// A table inside its expiration period is left out; anything uncertain is sent.
void main() {
  const cfg = {
    'products': TableRule(active: true, ttlSeconds: 3600),
    'categories': TableRule(active: false, ttlSeconds: 0),
    'payment-methods': TableRule(active: true, ttlSeconds: 0),
  };

  TableFreshness make(Stopwatch sw, [List<String>? saved]) => TableFreshness(
        stopwatch: sw,
        persist: (c, k) => saved?..addAll([c, k]),
      );

  test('no settings saved: everything is sent', () {
    final f = make(Stopwatch());
    expect(f.shouldSend('products', force: false), true);
  });

  test('switched off is never sent, even when forced', () {
    final f = make(Stopwatch())..onAnswer(serverTime: '2026-11-25T09:00:00Z', config: cfg);
    expect(f.shouldSend('categories', force: false), false);
    expect(f.shouldSend('categories', force: true), false);
  });

  test('no expiration period: sent every pull', () {
    final f = make(Stopwatch())..onAnswer(serverTime: '2026-11-25T09:00:00Z', config: cfg);
    f.markChecked('payment-methods', '2026-11-25T09:00:00Z');
    expect(f.shouldSend('payment-methods', force: false), true);
  });

  test('inside the period it is left out, after it it is sent, force always sends', () {
    final sw = Stopwatch();
    final f = make(sw)..onAnswer(serverTime: '2026-11-25T09:00:00Z', config: cfg);
    f.markChecked('products', '2026-11-25T08:30:00Z'); // period 1 h: fresh until 09:30
    expect(f.shouldSend('products', force: false), false);
    expect(f.shouldSend('products', force: true), true);
    // server clock = answer time + elapsed; fake it by re-anchoring later
    f.onAnswer(serverTime: '2026-11-25T09:31:00Z', config: cfg);
    expect(f.shouldSend('products', force: false), true);
  });

  test('never checked, or no clock reading yet (after a restart): sent', () {
    final f = make(Stopwatch());
    f.onAnswer(serverTime: null, config: cfg); // settings known, no anchor
    f.markChecked('products', '2026-11-25T08:59:00Z');
    expect(f.shouldSend('products', force: false), true);
    final g = make(Stopwatch())..onAnswer(serverTime: '2026-11-25T09:00:00Z', config: cfg);
    expect(g.shouldSend('products', force: false), true); // no checkedAt
  });

  test('settings and check times survive a restart, the clock does not', () {
    final saved = <String>[];
    final f = make(Stopwatch(), saved)..onAnswer(serverTime: '2026-11-25T09:00:00Z', config: cfg);
    f.markChecked('products', '2026-11-25T09:00:00Z');
    final g = TableFreshness(
        savedConfig: saved[saved.length - 2], savedChecked: saved.last, stopwatch: Stopwatch());
    expect(g.rule('categories')!.active, false);
    expect(g.rule('products')!.ttlSeconds, 3600);
    expect(g.checkedAt['products'], '2026-11-25T09:00:00Z');
    expect(g.serverNow(), isNull);
    expect(g.shouldSend('products', force: false), true); // unsure: asks, server says fresh
  });

  test('a reset clears every check time', () {
    final f = make(Stopwatch())..markChecked('products', '2026-11-25T09:00:00Z');
    f.clearChecked();
    expect(f.checkedAt, isEmpty);
  });

  test('bad saved text is ignored', () {
    final f = TableFreshness(savedConfig: 'x', savedChecked: '[', stopwatch: Stopwatch());
    expect(f.config, isEmpty);
    expect(f.checkedAt, isEmpty);
  });
}

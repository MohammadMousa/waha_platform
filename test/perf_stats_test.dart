import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waha_kiosk/data/db/app_database.dart';
import 'package:waha_kiosk/data/sync/sync_log_rules.dart';
import 'package:waha_kiosk/services/perf_stats.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final s = PerfStats.instance;

  setUp(() {
    s.setEnabled(false);
    s.reset();
  });
  tearDown(() => s.setEnabled(false));

  const ms = Duration(milliseconds: 1);

  test('with logging off nothing is counted', () {
    s.recordFrame(total: ms * 900, build: ms * 5, raster: ms * 5);
    s.recordDb(ms * 500, write: true);
    s.recordPull(took: ms * 1000, rows: 5);
    s.recordSound();
    expect(s.frames, 0);
    expect(s.dbWrites, 0);
    expect(s.pullsAttempted, 0);
    expect(s.sounds, 0);
    expect(s.snapshot(), startsWith('off'));
  });

  test('frames are counted by size', () {
    s.setEnabled(true);
    s.recordFrame(total: ms * 10, build: ms * 4, raster: ms * 6);
    s.recordFrame(total: ms * 150, build: ms * 100, raster: ms * 50);
    s.recordFrame(total: ms * 800, build: ms * 700, raster: ms * 100);
    expect(s.frames, 3);
    expect(s.framesOver100, 2);
    expect(s.framesOver700, 1);
    expect(s.worstFrameMs, 800);
    expect(s.snapshot(), contains('frames=3 over100ms=2 over700ms=1 worst=800ms'));
  });

  test('database and sound counters', () {
    s.setEnabled(true);
    s.recordDb(ms * 20, write: false);
    s.recordDb(ms * 250, write: true);
    s.recordSound();
    s.recordSound();
    expect(s.dbReads, 1);
    expect(s.dbWrites, 1);
    expect(s.dbSlow, 1);
    expect(s.dbMaxMs, 250);
    expect(s.sounds, 2);
  });

  test('pulls: completed, zero-row, paused and failed are told apart', () {
    s.setEnabled(true);
    s.recordPull(took: ms * 2000, rows: 0);
    s.recordPull(took: ms * 3000, rows: 7);
    s.recordPull(took: ms * 500, rows: 0, paused: true);
    s.recordPull(took: ms * 100, rows: 0, failed: true);
    expect(s.pullsAttempted, 4);
    expect(s.pullsCompleted, 2);
    expect(s.pullsZeroRow, 1);
    expect(s.pullRows, 7);
    expect(s.pullsPaused, 1);
    expect(s.pullsFailed, 1);
    expect(s.pullLongestMs, 3000);
    expect(s.lastPullOkAt, isNotNull);
  });

  test('turning logging off drops the counters, turning it on starts at zero', () {
    s.setEnabled(true);
    s.recordSound();
    s.setEnabled(false);
    expect(s.sounds, 0);
    s.setEnabled(true);
    expect(s.sounds, 0);
  });

  test('the database wrapper counts real statements, only while logging is on', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customSelect('select 1').get(); // opens the database, logging off
    expect(s.dbReads + s.dbWrites, 0);
    s.setEnabled(true);
    await db.customSelect('select 1').get();
    await db.customStatement('create table t_perf (x integer)');
    expect(s.dbReads, greaterThanOrEqualTo(1));
    expect(s.dbWrites, greaterThanOrEqualTo(1));
  });

  group('sync log rules', () {
    test('at Info every feed line is written', () {
      expect(SyncLogRules.logFeed(detailed: true, rows: 0), isTrue);
    });
    test('at Warn only a feed that brought rows is written', () {
      expect(SyncLogRules.logFeed(detailed: false, rows: 0), isFalse);
      expect(SyncLogRules.logFeed(detailed: false, rows: 3), isTrue);
    });
    test('summary: rows, failure and the first success since start show at Warn', () {
      bool at(int rows, bool failed, bool first) => SyncLogRules.logPullSummary(
          detailed: false, rows: rows, failed: failed, firstOkSinceStart: first);
      expect(at(0, false, false), isFalse);
      expect(at(4, false, false), isTrue);
      expect(at(0, true, false), isTrue);
      expect(at(0, false, true), isTrue);
    });
  });
}

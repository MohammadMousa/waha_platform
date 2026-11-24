import 'package:drift/drift.dart';

import '../../services/perf_stats.dart';

/// Times every local database statement for [PerfStats] (counts, total and
/// slowest time, how many took over 100 ms). Counters only, no locks, no log
/// line per statement; when logging is off [PerfStats.enabled] is false and a
/// statement costs one boolean check.
class DbTimingInterceptor extends QueryInterceptor {
  Future<T> _time<T>(bool write, Future<T> Function() run) async {
    if (!PerfStats.instance.enabled) return run();
    final sw = Stopwatch()..start();
    try {
      return await run();
    } finally {
      PerfStats.instance.recordDb(sw.elapsed, write: write);
    }
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
          QueryExecutor executor, String statement, List<Object?> args) =>
      _time(false, () => executor.runSelect(statement, args));

  @override
  Future<int> runInsert(
          QueryExecutor executor, String statement, List<Object?> args) =>
      _time(true, () => executor.runInsert(statement, args));

  @override
  Future<int> runUpdate(
          QueryExecutor executor, String statement, List<Object?> args) =>
      _time(true, () => executor.runUpdate(statement, args));

  @override
  Future<int> runDelete(
          QueryExecutor executor, String statement, List<Object?> args) =>
      _time(true, () => executor.runDelete(statement, args));

  @override
  Future<void> runCustom(
          QueryExecutor executor, String statement, List<Object?> args) =>
      _time(true, () => executor.runCustom(statement, args));

  @override
  Future<void> runBatched(
          QueryExecutor executor, BatchedStatements statements) =>
      _time(true, () => executor.runBatched(statements));
}

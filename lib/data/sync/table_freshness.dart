import 'dart:convert';

import '../../services/local_prefs.dart';

/// The server's setting for one table (combined pull): switched on or off,
/// and how long a device may go without checking it again (0 = every pull).
class TableRule {
  final bool active;
  final int ttlSeconds;
  const TableRule({required this.active, required this.ttlSeconds});
}

/// The table settings the server sent, when each table was last fully checked,
/// and a way to tell whether a table is still fresh.
///
/// "Fresh" is judged in SERVER time: the server time of the last answer plus
/// the time passed since on a monotonic stopwatch. After an app restart there
/// is no anchor, so nothing can be judged and every table is sent; the server
/// then answers "fresh" without querying. Both maps are small text copies in
/// the saved preferences (no database table).
class TableFreshness {
  TableFreshness({
    String? savedConfig,
    String? savedChecked,
    void Function(String config, String checked)? persist,
    Stopwatch? stopwatch,
  })  : _persist = persist ?? _persistToPrefs,
        _sw = stopwatch ?? Stopwatch() {
    _config = _readConfig(savedConfig);
    _checked = _readChecked(savedChecked);
  }

  /// Loads the copies kept in the saved preferences.
  factory TableFreshness.fromPrefs() => TableFreshness(
        savedConfig: LocalPrefs.syncTableConfig,
        savedChecked: LocalPrefs.syncCheckedAt,
      );

  static void _persistToPrefs(String config, String checked) {
    LocalPrefs.setSyncTableConfig(config);
    LocalPrefs.setSyncCheckedAt(checked);
  }

  final void Function(String config, String checked) _persist;
  final Stopwatch _sw;
  Map<String, TableRule> _config = {};
  Map<String, String> _checked = {};
  DateTime? _anchor;

  Map<String, TableRule> get config => _config;
  Map<String, String> get checkedAt => Map.unmodifiable(_checked);

  static Map<String, TableRule> _readConfig(String? raw) {
    if (raw == null) return {};
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return {for (final e in m.entries) e.key: _rule(e.value)};
    } catch (_) {
      return {};
    }
  }

  static TableRule _rule(Object? v) {
    final m = v as Map<String, dynamic>;
    return TableRule(
      active: m['active'] as bool? ?? true,
      ttlSeconds: (m['ttlSeconds'] as num?)?.toInt() ?? 0,
    );
  }

  static Map<String, String> _readChecked(String? raw) {
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }

  static Map<String, TableRule> parseConfig(Object? json) {
    if (json is! Map) return {};
    try {
      return {for (final e in json.entries) e.key as String: _rule(e.value)};
    } catch (_) {
      return {};
    }
  }

  /// Server time now, or null when it cannot be told (no answer seen since the app started).
  DateTime? serverNow() {
    return _anchor?.add(_sw.elapsed);
  }

  /// Takes the table settings and the clock reading from an answer.
  void onAnswer(
      {required String? serverTime, required Map<String, TableRule> config}) {
    if (config.isNotEmpty) _config = config;
    final t = DateTime.tryParse(serverTime ?? '');
    if (t != null) {
      _anchor = t.toUtc();
      _sw
        ..reset()
        ..start();
    }
    _save();
  }

  /// A table finished (came back `last`) in the answer stamped [serverTime].
  void markChecked(String table, String? serverTime) {
    if (serverTime == null) return;
    _checked[table] = serverTime;
    _save();
  }

  /// The table was emptied by hand: it has no finished check any more.
  void forget(String table) {
    _checked.remove(table);
    _save();
  }

  /// Every table must be pulled in full again (the server asked for a reset).
  void clearChecked() {
    _checked = {};
    _save();
  }

  /// The settings of a table, or null when the server never said.
  TableRule? rule(String table) => _config[table];

  /// False when the table is switched off, or (unless [force]) still inside
  /// its expiration period. When unsure, true: the server decides.
  bool shouldSend(String table, {required bool force}) {
    final r = _config[table];
    if (r == null) return true;
    if (!r.active) return false;
    if (force || r.ttlSeconds <= 0) return true;
    final c = _checked[table];
    final now = serverNow();
    if (c == null || now == null) return true;
    final at = DateTime.tryParse(c);
    if (at == null) return true;
    return !at.toUtc().add(Duration(seconds: r.ttlSeconds)).isAfter(now);
  }

  void _save() {
    try {
      _persist(
        jsonEncode({
          for (final e in _config.entries)
            e.key: {'active': e.value.active, 'ttlSeconds': e.value.ttlSeconds},
        }),
        jsonEncode(_checked),
      );
    } catch (_) {}
  }
}

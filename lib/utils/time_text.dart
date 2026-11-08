import '../l10n/generated/app_localizations.dart';

/// How long ago [t] was, in the two largest units: `2d 3h`, `4h 10m`, `35s`.
/// Under 5 seconds (or in the future) it is "just now". Texts come from the
/// language files so Arabic reads naturally too.
String agoText(AppLocalizations l, DateTime t, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inSeconds < 5) return l.timeJustNow;
  final parts = <String>[
    if (d.inDays > 0) l.timeDays('${d.inDays}'),
    if (d.inHours % 24 > 0 || d.inDays > 0) l.timeHours('${d.inHours % 24}'),
    if (d.inMinutes % 60 > 0 || d.inHours > 0)
      l.timeMinutes('${d.inMinutes % 60}'),
    if (d.inHours == 0) l.timeSeconds('${d.inSeconds % 60}'),
  ];
  // Two largest units, skipping empty "0" leftovers in the middle.
  final shown = parts.where((p) => !p.startsWith('0')).take(2).toList();
  return l.timeAgo(shown.isEmpty ? parts.first : shown.join(' '));
}

/// 12-hour clock with AM/PM (ص/م in Arabic): `3:41 PM`. Date added when [t]
/// is not today: `07 Nov 3:41 PM`.
String clock12(AppLocalizations l, DateTime t, {DateTime? now}) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final m = t.minute.toString().padLeft(2, '0');
  final suffix = t.hour < 12 ? l.timeAm : l.timePm;
  final n = now ?? DateTime.now();
  final today = t.year == n.year && t.month == n.month && t.day == n.day;
  if (today) return '$h:$m $suffix';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${t.day.toString().padLeft(2, '0')} ${months[t.month - 1]} $h:$m $suffix';
}

/// `4m ago (3:41 PM)` — the form every sync time in Settings uses.
String whenText(AppLocalizations l, DateTime? t, {DateTime? now}) =>
    t == null ? '-' : '${agoText(l, t, now: now)} (${clock12(l, t, now: now)})';

/// Same, from a saved ISO text (the database keeps UTC strings).
String whenIsoText(AppLocalizations l, String? iso, {DateTime? now}) =>
    whenText(l, iso == null ? null : DateTime.tryParse(iso)?.toLocal(), now: now);

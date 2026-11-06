import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// Saves the body of GET /api/sync/device-config as the single cached row.
Future<void> saveDeviceConfig(AppDatabase db, Map<String, dynamic> json) async {
  int i(String k) => (json[k] as num).toInt();
  await db.into(db.deviceSettings).insertOnConflictUpdate(
        DeviceSettingsCompanion(
          id: const Value(1),
          deviceId: Value(i('deviceId')),
          deviceNo: Value(i('deviceNo')),
          storeId: Value(i('storeId')),
          organizationId: Value(i('organizationId')),
          currency: Value(json['currency'] as String),
          vatRate: Value(json['vatRate'].toString()),
          pricesIncludeVat: Value(json['pricesIncludeVat'] as bool? ?? true),
          shortCode: Value(_blankToNull(json['shortCode'] as String?)),
          invoiceBaseUrl: Value(_blankToNull(json['invoiceBaseUrl'] as String?)),
          lastReferenceSerial: Value((json['lastReferenceSerial'] as num?)?.toInt()),
          fetchedAt: Value(DateTime.now().toUtc().toIso8601String()),
        ),
      );
}

/// The cached device settings, or null if none were ever fetched.
Future<DeviceSetting?> readDeviceSettings(AppDatabase db) =>
    (db.select(db.deviceSettings)..where((t) => t.id.equals(1))).getSingleOrNull();

/// The newest `lastPullAt` over all feeds, for the status report.
Future<String?> latestPullAt(AppDatabase db) async {
  final rows = await db.select(db.syncState).get();
  final times = [for (final r in rows) if (r.lastPullAt != null) r.lastPullAt!]
    ..sort();
  return times.isEmpty ? null : times.last;
}

String? _blankToNull(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waha_kiosk/data/db/app_database.dart';
import 'package:waha_kiosk/data/sync/sync_engine.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('the reset empties the store payment method rows and their position only', () async {
    for (final id in [1, 2]) {
      await db.into(db.localStorePaymentMethods).insert(
          LocalStorePaymentMethodsCompanion.insert(
              id: Value(id),
              paymentMethodId: 1,
              active: id == 1,
              updatedAt: '2026-11-25T08:00:00Z'));
    }
    for (final feed in ['store-payment-methods', 'payment-methods']) {
      await db.into(db.syncState).insert(SyncStateCompanion.insert(
          feed: feed, since: const Value('2026-11-25T08:00:00Z')));
    }

    await SyncEngine.clearStorePaymentMethods(db);

    expect(await db.select(db.localStorePaymentMethods).get(), isEmpty);
    final left = await db.select(db.syncState).get();
    expect(left.map((s) => s.feed), ['payment-methods']);
  });
}

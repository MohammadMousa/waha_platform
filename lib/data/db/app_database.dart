import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

// One local database for everything the kiosk keeps offline. Row shapes follow
// the pull feeds in the backend's offline.md (section 2). Names and
// descriptions are kept as the raw JSON text the server sends ({"ar","en"}).
// Inactive rows are kept on purpose: a deactivated product must reach the
// device, and the order screens filter on `active`.

@TableIndex(name: 'idx_products_barcode', columns: {#barcode})
class LocalProducts extends Table {
  IntColumn get id => integer()();
  TextColumn get barcode => text().nullable()();
  TextColumn get sku => text().nullable()();
  TextColumn get nameJson => text()();
  TextColumn get descriptionJson => text().nullable()();
  // Prices travel as decimal text so no binary rounding sneaks in.
  TextColumn get price => text()(); // excluding VAT
  TextColumn get priceWithVat => text()();
  BoolColumn get active => boolean()();
  BoolColumn get isPublic => boolean()();
  IntColumn get categoryId => integer().nullable()();
  IntColumn get imageResourceId => integer().nullable()();
  TextColumn get updatedAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}

@TableIndex(name: 'idx_barcodes_barcode', columns: {#barcode})
@TableIndex(name: 'idx_barcodes_product', columns: {#productId})
class LocalBarcodes extends Table {
  IntColumn get id => integer()();
  IntColumn get productId => integer()();
  TextColumn get barcode => text()();
  BoolColumn get isPrimary => boolean()();
  TextColumn get updatedAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalCategories extends Table {
  IntColumn get id => integer()();
  TextColumn get nameJson => text()();
  TextColumn get key => text().nullable()();
  BoolColumn get isPublic => boolean()();
  BoolColumn get active => boolean()();
  IntColumn get sortOrder => integer()();
  IntColumn get imageResourceId => integer().nullable()();
  TextColumn get updatedAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalPaymentMethods extends Table {
  IntColumn get id => integer()();
  TextColumn get key => text()();
  TextColumn get displayNameJson => text().nullable()();
  TextColumn get provider => text()();
  TextColumn get availableModes => text().nullable()();
  BoolColumn get offlineCapable => boolean()();
  BoolColumn get active => boolean()();
  IntColumn get sortOrder => integer()();
  TextColumn get paymentUrl => text().nullable()();
  TextColumn get updatedAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalStorePaymentMethods extends Table {
  IntColumn get id => integer()();
  IntColumn get paymentMethodId => integer()();
  BoolColumn get active => boolean()();
  IntColumn get sortOrder => integer().nullable()();
  TextColumn get updatedAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}

// Image records only. The picture files are still fetched on demand.
class LocalProductImages extends Table {
  IntColumn get id => integer()();
  IntColumn get productId => integer()();
  IntColumn get resourceId => integer()();
  IntColumn get sortOrder => integer()();
  TextColumn get updatedAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}

// One row per feed: the saved cursor and whether one full pull ever finished.
// `since` is the server's own text for the instant, kept exactly as sent.
/// One row per saved resource (a product image, the landing page, a file the
/// landing page uses), keyed by the address the kiosk asked for. The bytes
/// are NOT here: they are files in one folder, named by the hash of their
/// content, so two addresses with the same bytes share one file. This table
/// only says which address maps to which file and when it was last checked
/// and shown. See lib/data/resources/resource_cache.dart.
class CachedResources extends Table {
  TextColumn get address => text()(); // e.g. /api/resources/125, /resource/waha/pages/x.png
  TextColumn get mimeType => text()(); // from the response's Content-Type
  TextColumn get etag => text().nullable()(); // exactly as the server sent it, quotes included
  TextColumn get fileHash => text()(); // sha256 of the bytes = the file's name
  IntColumn get sizeBytes => integer()();
  TextColumn get createdAt => text()();
  TextColumn get lastCheckedAt => text()(); // last time the server confirmed or sent it
  TextColumn get lastUsedAt => text()(); // last time it was shown (decides what to remove)

  @override
  Set<Column> get primaryKey => {address};
}

class SyncState extends Table {
  TextColumn get feed => text()();
  TextColumn get since => text().nullable()();
  IntColumn get afterId => integer().withDefault(const Constant(0))();
  BoolColumn get fullPullDone => boolean().withDefault(const Constant(false))();
  TextColumn get lastPullAt => text().nullable()();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column> get primaryKey => {feed};
}

// What `GET /api/sync/device-config` returned last, so the kiosk can start
// without the server. Always one row (id = 1).
class DeviceSettings extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  IntColumn get deviceId => integer()();
  IntColumn get deviceNo => integer()();
  IntColumn get storeId => integer()();
  IntColumn get organizationId => integer()();
  TextColumn get currency => text()();
  // Decimal text (e.g. "0.15"), never a binary double, for exact tax maths.
  TextColumn get vatRate => text()();
  BoolColumn get pricesIncludeVat => boolean()();
  TextColumn get shortCode => text().nullable()();
  // Public host for the invoice QR link: <invoiceBaseUrl>/api/invoices/<uuid>.
  TextColumn get invoiceBaseUrl => text().nullable()();
  // Serial of this device's latest order reference on the server (null = none).
  IntColumn get lastReferenceSerial => integer().nullable()();
  TextColumn get fetchedAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}

// ---- Local orders (offline mode) ------------------------------------------
// An order made on the device. Money is exact decimal text, never a double.
// syncState: LOCAL (not paid, stays here) -> PENDING (paid, waiting to push)
// -> SYNCED, or DEAD (permanent push error, kept for the dead-letter list).
// PAY_PENDING: the order was made ON the server (caching mode) and the card
// was approved, but the server could not be told; only the payment still has
// to be sent. These rows have no lines of their own, so they are never sent
// as a whole order.
@TableIndex(name: 'idx_orders_sync', columns: {#syncState, #nextAttemptAt})
class LocalOrders extends Table {
  TextColumn get orderId => text()(); // UUID v7, made on the device
  TextColumn get orderReference => text()();
  // The server's own order number, filled from the push response.
  IntColumn get displayId => integer().nullable()();
  IntColumn get storeId => integer()();
  TextColumn get username => text().nullable()();
  TextColumn get status => text()(); // CREATED | PAID | CANCELLED
  TextColumn get currency => text()();
  TextColumn get taxRate => text()();
  TextColumn get subtotalAmount => text()();
  TextColumn get taxAmount => text()();
  TextColumn get totalAmount => text()();
  TextColumn get createdAt => text()();
  TextColumn get paidAt => text().nullable()();
  TextColumn get syncState => text().withDefault(const Constant('LOCAL'))();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get nextAttemptAt => text().nullable()();
  TextColumn get lastErrorCode => text().nullable()();
  TextColumn get lastError => text().nullable()();
  TextColumn get syncedAt => text().nullable()();

  @override
  Set<Column> get primaryKey => {orderId};
}

class LocalOrderItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get orderId => text().references(LocalOrders, #orderId)();
  IntColumn get lineNo => integer()();
  IntColumn get productId => integer()();
  IntColumn get quantity => integer()();
  TextColumn get unitPrice => text()();
  TextColumn get lineNet => text()();
  TextColumn get lineTax => text()();
  TextColumn get nameJson => text().nullable()();
  // The unit price the customer saw (with VAT when prices include VAT).
  TextColumn get displayUnitPrice => text().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {orderId, lineNo},
      ];
}

// Only successful (PAID) payments are stored and sent.
class LocalPayments extends Table {
  TextColumn get paymentId => text()(); // UUID made on the device
  TextColumn get orderId => text().references(LocalOrders, #orderId)();
  TextColumn get provider => text()();
  TextColumn get outcome => text()();
  TextColumn get providerReference => text().nullable()();
  TextColumn get authCode => text().nullable()();
  TextColumn get notesJson => text().nullable()();
  BoolColumn get lateApproval => boolean().withDefault(const Constant(false))();
  TextColumn get createdAt => text()();
  // When the server accepted this payment (null = not sent yet). Together
  // with the order's own sync state it decides what to send: order not sent
  // -> the whole order; order on the server but payment not -> payment only.
  TextColumn get syncedAt => text().nullable()();

  @override
  Set<Column> get primaryKey => {paymentId};
}

// One row: the last reference serial this device handed out.
class ReferenceCounter extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  IntColumn get lastSerial => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [
  LocalProducts,
  LocalBarcodes,
  LocalCategories,
  LocalPaymentMethods,
  LocalStorePaymentMethods,
  LocalProductImages,
  SyncState,
  DeviceSettings,
  LocalOrders,
  LocalOrderItems,
  LocalPayments,
  ReferenceCounter,
  CachedResources,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? driftDatabase(name: 'waha_kiosk'));

  // Bump this for every schema change and add a step in [migration].
  // Never edit an old step: devices in the field run them in order.
  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          // Steps run in order, one per version. Never edit an old step.
          if (from < 2) {
            await m.createTable(deviceSettings);
          }
          if (from < 3) {
            await m.createTable(localOrders);
            await m.createTable(localOrderItems);
            await m.createTable(localPayments);
            await m.createTable(referenceCounter);
          }
          if (from < 3) {
            // Indexes that older dev builds created by hand or not at all.
            await customStatement(
                'CREATE INDEX IF NOT EXISTS idx_products_barcode ON local_products (barcode)');
            await customStatement(
                'CREATE INDEX IF NOT EXISTS idx_barcodes_barcode ON local_barcodes (barcode)');
            await customStatement(
                'CREATE INDEX IF NOT EXISTS idx_barcodes_product ON local_barcodes (product_id)');
            await customStatement(
                'CREATE INDEX IF NOT EXISTS idx_orders_sync ON local_orders (sync_state, next_attempt_at)');
          }
          if (from < 4) {
            // createTable above builds a table with its CURRENT columns, so a
            // column added later already exists when that table was just
            // created in this same upgrade. Only tables that existed before
            // this version get the column added.
            if (from >= 3) {
              await m.addColumn(localOrderItems, localOrderItems.displayUnitPrice);
            }
            if (from >= 2) {
              await m.addColumn(deviceSettings, deviceSettings.invoiceBaseUrl);
            }
          }
          if (from < 5) {
            // Tables created in this same upgrade (from < 3) already have the
            // column; older ones get it now. Payments of orders the server
            // already holds count as sent.
            if (from >= 3) {
              await m.addColumn(localPayments, localPayments.syncedAt);
            }
            await customStatement(
                'UPDATE local_payments SET synced_at = (SELECT synced_at FROM local_orders '
                "WHERE local_orders.order_id = local_payments.order_id AND local_orders.sync_state = 'SYNCED') "
                'WHERE synced_at IS NULL');
          }
          if (from < 6) {
            await m.createTable(cachedResources);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}

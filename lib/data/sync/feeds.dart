import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// The pull feeds, in the order they are pulled. `path` is the table name in
/// GET /api/sync/{path}.
const List<String> kSyncFeeds = [
  'products',
  'barcodes',
  'categories',
  'payment-methods',
  'store-payment-methods',
  'product-images',
];

/// Feeds the kiosk must have fully pulled once before it may take orders.
const List<String> kRequiredFeeds = ['products', 'barcodes', 'payment-methods'];

String? _s(Object? v) => v?.toString();
int? _i(Object? v) => v == null ? null : (v as num).toInt();
// Names arrive as JSON objects; keep them as compact JSON text.
String? _json(Object? v) => v == null ? null : jsonEncode(v);

/// Writes one page of items into its table with upsert. Runs inside the
/// caller's transaction, together with the cursor update.
Future<void> upsertPage(
    AppDatabase db, String feed, List<Map<String, dynamic>> items) async {
  await db.batch((b) {
    for (final m in items) {
      switch (feed) {
        case 'products':
          b.insert(
              db.localProducts,
              LocalProductsCompanion.insert(
                id: Value(_i(m['id'])!),
                barcode: Value(_s(m['barcode'])),
                sku: Value(_s(m['sku'])),
                nameJson: _json(m['name']) ?? '{}',
                descriptionJson: Value(_json(m['description'])),
                price: _s(m['price']) ?? '0',
                priceWithVat: _s(m['priceWithVat']) ?? _s(m['price']) ?? '0',
                active: (m['active'] as bool?) ?? true,
                isPublic: (m['public'] as bool?) ?? true,
                categoryId: Value(_i(m['categoryId'])),
                imageResourceId: Value(_i(m['imageResourceId'])),
                updatedAt: _s(m['updatedAt']) ?? '',
              ),
              mode: InsertMode.insertOrReplace);
        case 'barcodes':
          b.insert(
              db.localBarcodes,
              LocalBarcodesCompanion.insert(
                id: Value(_i(m['id'])!),
                productId: _i(m['productId'])!,
                barcode: _s(m['barcode']) ?? '',
                isPrimary: (m['primary'] as bool?) ?? false,
                updatedAt: _s(m['updatedAt']) ?? '',
              ),
              mode: InsertMode.insertOrReplace);
        case 'categories':
          b.insert(
              db.localCategories,
              LocalCategoriesCompanion.insert(
                id: Value(_i(m['id'])!),
                nameJson: _json(m['name']) ?? '{}',
                key: Value(_s(m['key'])),
                isPublic: (m['public'] as bool?) ?? true,
                active: (m['active'] as bool?) ?? true,
                sortOrder: _i(m['sortOrder']) ?? 0,
                imageResourceId: Value(_i(m['imageResourceId'])),
                updatedAt: _s(m['updatedAt']) ?? '',
              ),
              mode: InsertMode.insertOrReplace);
        case 'payment-methods':
          b.insert(
              db.localPaymentMethods,
              LocalPaymentMethodsCompanion.insert(
                id: Value(_i(m['id'])!),
                key: _s(m['key']) ?? '',
                displayNameJson: Value(_json(m['displayName'])),
                provider: _s(m['provider']) ?? '',
                availableModes: Value(_s(m['availableModes'])),
                offlineCapable: (m['offlineCapable'] as bool?) ?? false,
                active: (m['active'] as bool?) ?? true,
                sortOrder: _i(m['sortOrder']) ?? 0,
                paymentUrl: Value(_s(m['paymentUrl'])),
                updatedAt: _s(m['updatedAt']) ?? '',
              ),
              mode: InsertMode.insertOrReplace);
        case 'store-payment-methods':
          b.insert(
              db.localStorePaymentMethods,
              LocalStorePaymentMethodsCompanion.insert(
                id: Value(_i(m['id'])!),
                paymentMethodId: _i(m['paymentMethodId'])!,
                active: (m['active'] as bool?) ?? true,
                sortOrder: Value(_i(m['sortOrder'])),
                updatedAt: _s(m['updatedAt']) ?? '',
              ),
              mode: InsertMode.insertOrReplace);
        case 'product-images':
          b.insert(
              db.localProductImages,
              LocalProductImagesCompanion.insert(
                id: Value(_i(m['id'])!),
                productId: _i(m['productId'])!,
                resourceId: _i(m['resourceId'])!,
                sortOrder: _i(m['sortOrder']) ?? 0,
                updatedAt: _s(m['updatedAt']) ?? '',
              ),
              mode: InsertMode.insertOrReplace);
        default:
          throw ArgumentError('Unknown feed: $feed');
      }
    }
  });
}

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../db/app_database.dart';
import '../sync/device_settings.dart';
import '../../config/app_config.dart';
import '../../models/order.dart';
import '../../models/terminal_session.dart';
import '../../models/quote.dart';
import 'decimal.dart';
import 'order_reference.dart';
import 'pricing.dart';

/// A cart line for a new local order, with the product name kept for display.
class NewOrderLine {
  final int productId;
  final int quantity;
  final String unitPrice; // price EXCLUDING VAT, from the pulled product
  final String? nameJson;
  /// The price the customer saw (with VAT when prices include VAT).
  final String? displayUnitPrice;
  const NewOrderLine({
    required this.productId,
    required this.quantity,
    required this.unitPrice,
    this.nameJson,
    this.displayUnitPrice,
  });
}

/// A successful terminal payment, as the USB callback reports it.
class PaidPayment {
  final String provider; // e.g. "terminal"
  final String? providerReference;
  final String? authCode;
  final Map<String, dynamic>? notes;
  final bool lateApproval;
  const PaidPayment({
    required this.provider,
    this.providerReference,
    this.authCode,
    this.notes,
    this.lateApproval = false,
  });
}

class MissingDeviceSettings implements Exception {
  const MissingDeviceSettings();
  @override
  String toString() => 'Device settings were never fetched from the server';
}

/// Creates and updates orders in the local database. Pushing them to the
/// server is a separate step (the push scheduler).
class LocalOrderService {
  final AppDatabase db;
  final Uuid _uuid;
  final DateTime Function() _now;

  LocalOrderService(this.db, {Uuid? uuid, DateTime Function()? now})
      : _uuid = uuid ?? const Uuid(),
        _now = now ?? DateTime.now;

  String _iso() => _now().toUtc().toIso8601String();

  /// Prices the cart locally and saves a new unpaid order. The order id, the
  /// reference and the serial counter are written in ONE transaction, so a
  /// crash never hands out the same reference twice.
  Future<LocalOrder> createOrder({
    required List<NewOrderLine> lines,
    String? username,
    String? orderId,
  }) async {
    // Asking again for an order id that already exists (a retry after a
    // failed screen change) returns that order: nothing is created twice.
    if (orderId != null) {
      final existing = await findOrder(orderId);
      if (existing != null) return existing;
    }
    final settings = await readDeviceSettings(db);
    if (settings == null) throw const MissingDeviceSettings();
    final priced = priceCart(
      [for (final l in lines) PricingInput(l.productId, l.quantity, l.unitPrice)],
      vatRate: settings.vatRate,
    );
    return db.transaction(() async {
      final counter = await (db.select(db.referenceCounter)
            ..where((t) => t.id.equals(1)))
          .getSingleOrNull();
      // No local counter means a fresh install or a reinstall: continue from
      // what the server last saw for this device.
      final serial = nextSerial(counter?.lastSerial ?? settings.lastReferenceSerial);
      await db.into(db.referenceCounter).insertOnConflictUpdate(
            ReferenceCounterCompanion(id: const Value(1), lastSerial: Value(serial)),
          );
      orderId ??= _uuid.v7();
      final reference = buildReference(
        shortCode: settings.shortCode,
        storeId: settings.storeId,
        deviceNo: settings.deviceNo,
        serial: serial,
      );
      await db.into(db.localOrders).insert(LocalOrdersCompanion.insert(
            orderId: orderId!,
            orderReference: reference,
            storeId: settings.storeId,
            username: Value(username),
            status: 'CREATED',
            currency: settings.currency,
            taxRate: settings.vatRate,
            subtotalAmount: priced.subtotal,
            taxAmount: priced.tax,
            totalAmount: priced.total,
            createdAt: _iso(),
          ));
      for (var i = 0; i < priced.lines.length; i++) {
        final p = priced.lines[i];
        await db.into(db.localOrderItems).insert(LocalOrderItemsCompanion.insert(
              orderId: orderId!,
              lineNo: p.lineNo,
              productId: p.productId,
              quantity: p.quantity,
              unitPrice: p.unitPrice,
              lineNet: p.net,
              lineTax: p.tax,
              nameJson: Value(lines[i].nameJson),
              displayUnitPrice: Value(lines[i].displayUnitPrice),
            ));
      }
      return (db.select(db.localOrders)..where((t) => t.orderId.equals(orderId!)))
          .getSingle();
    });
  }

  /// Saves the approved payment and marks the order PAID and ready to push,
  /// in one transaction. Calling it again for the same payment id changes
  /// nothing (the terminal callback can fire several times per payment).
  Future<void> markPaid(String orderId, PaidPayment pay, {String? paymentId}) async {
    await db.transaction(() async {
      final order = await (db.select(db.localOrders)
            ..where((t) => t.orderId.equals(orderId)))
          .getSingle();
      final id = paymentId ?? _uuid.v4();
      final existing = await (db.select(db.localPayments)
            ..where((t) => t.paymentId.equals(id)))
          .getSingleOrNull();
      if (existing != null) return;
      // The same terminal transaction (same reference/RRN) is one payment,
      // however many times the callback reports it.
      final ref = pay.providerReference;
      if (ref != null && ref.isNotEmpty) {
        final same = await (db.select(db.localPayments)
              ..where((t) => t.orderId.equals(orderId) & t.providerReference.equals(ref)))
            .getSingleOrNull();
        if (same != null) return;
      }
      await db.into(db.localPayments).insert(LocalPaymentsCompanion.insert(
            paymentId: id,
            orderId: orderId,
            provider: pay.provider,
            outcome: 'PAID',
            providerReference: Value(pay.providerReference),
            authCode: Value(pay.authCode),
            notesJson: Value(pay.notes == null ? null : jsonEncode(pay.notes)),
            lateApproval: Value(pay.lateApproval),
            createdAt: _iso(),
          ));
      final now = _iso();
      await (db.update(db.localOrders)..where((t) => t.orderId.equals(orderId)))
          .write(LocalOrdersCompanion(
        status: const Value('PAID'),
        paidAt: Value(order.paidAt ?? now),
        // A dead-lettered order stays dead; everything else is ready to push.
        // A dead-lettered order stays dead. An order the server already
        // holds gets this new payment sent on its own (payment only). Anything
        // else is ready to push as a whole order.
        syncState: Value(switch (order.syncState) {
          'DEAD' => 'DEAD',
          'PAY_PENDING' => 'PAY_PENDING',
          'SYNCED' => 'PAY_PENDING',
          _ => 'PENDING',
        }),
      ));
    });
  }

  /// A payment the SERVER took (a QR link): the server holds the payment, so
  /// this device creates none and sends nothing more. Only the local copy is
  /// brought up to date (status, paid time, the server's order number). The
  /// sync state is left alone: an order that was sent unpaid stays SYNCED.
  Future<void> markPaidOnServer(String orderId, {int? displayId}) async {
    final o = await findOrder(orderId);
    if (o == null || o.status == 'PAID') return;
    await (db.update(db.localOrders)..where((t) => t.orderId.equals(orderId)))
        .write(LocalOrdersCompanion(
      status: const Value('PAID'),
      paidAt: Value(o.paidAt ?? _iso()),
      displayId: displayId == null ? const Value.absent() : Value(displayId),
    ));
  }

  /// Caching mode: the order was made ON the server and the card was approved,
  /// but the server could not be told. Keeps a record of the order (just
  /// enough to send the payment later, no lines) and the approved payment, in
  /// one transaction, marked to send as a payment only. Calling it again for
  /// the same payment changes nothing.
  Future<void> keepPaymentOfServerOrder({
    required String orderId,
    required PaidPayment pay,
    required String paymentId,
    WahaOrder? order,
    TerminalSession? session,
  }) async {
    final settings = await readDeviceSettings(db);
    final now = _iso();
    final total = order?.total ?? session?.amount ?? 0;
    final existing = await findOrder(orderId);
    if (existing == null) {
      await db.into(db.localOrders).insert(LocalOrdersCompanion.insert(
            orderId: orderId,
            orderReference: order?.orderReference ??
                (order?.displayId != null ? '#${order!.displayId}' : orderId),
            displayId: Value(order?.displayId),
            storeId: order?.storeId ?? settings?.storeId ?? 0,
            username: Value(order?.username),
            status: 'CREATED',
            currency: order?.currency ?? session?.currency ?? settings?.currency ?? '',
            taxRate: order?.taxRate?.toString() ?? settings?.vatRate ?? '0',
            subtotalAmount: (order?.subtotal ?? total).toStringAsFixed(2),
            taxAmount: (order?.tax ?? 0).toStringAsFixed(2),
            totalAmount: total.toStringAsFixed(2),
            createdAt: order?.createdAt ?? now,
            syncState: const Value('PAY_PENDING'),
          ));
    }
    await markPaid(orderId, pay, paymentId: paymentId);
    // The order is on the server already: a payment-only send is enough.
    await (db.update(db.localOrders)
          ..where((t) => t.orderId.equals(orderId) & t.syncState.equals('LOCAL')))
        .write(const LocalOrdersCompanion(syncState: Value('PAY_PENDING')));
  }

  /// Body of the payment-only send: only the payments the server has not
  /// accepted yet. The lines are not part of it.
  Future<Map<String, dynamic>> buildPaymentPushBody(String orderId) async {
    final o = await (db.select(db.localOrders)..where((t) => t.orderId.equals(orderId)))
        .getSingle();
    final pays = await (db.select(db.localPayments)
          ..where((t) =>
              t.orderId.equals(orderId) & t.outcome.equals('PAID') & t.syncedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
    return {
      'totalAmount': num.parse(o.totalAmount),
      'payments': [for (final p in pays) _paymentJson(p)],
    };
  }

  Map<String, dynamic> _paymentJson(LocalPayment p) => {
        'paymentId': p.paymentId,
        'provider': p.provider,
        'outcome': p.outcome,
        if (p.providerReference != null) 'providerReference': p.providerReference,
        'createdAt': p.createdAt,
        if (p.authCode != null) 'authCode': p.authCode,
        if (p.notesJson != null) 'notes': jsonDecode(p.notesJson!),
        'lateApproval': p.lateApproval,
      };

  Future<LocalOrder?> findOrder(String orderId) =>
      (db.select(db.localOrders)..where((t) => t.orderId.equals(orderId)))
          .getSingleOrNull();

  /// The order in the shape the invoice screens already read. The invoice
  /// link is the same one the server would give, <invoiceBaseUrl>/api/invoices/<uuid>,
  /// plus the marker ?offline=1. Every order made on this device gets the
  /// marker (even if it is sent to the server a moment later): the server may
  /// not have the order yet, and with the marker it shows a waiting page
  /// instead of a 404. Orders made on the server keep the plain link.
  Future<WahaOrder?> toWahaOrder(String orderId) async {
    final o = await findOrder(orderId);
    if (o == null) return null;
    final settings = await readDeviceSettings(db);
    final items = await (db.select(db.localOrderItems)
          ..where((t) => t.orderId.equals(orderId))
          ..orderBy([(t) => OrderingTerm.asc(t.lineNo)]))
        .get();
    final pay = await (db.select(db.localPayments)
          ..where((t) => t.orderId.equals(orderId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(1))
        .getSingleOrNull();
    final base = (settings?.invoiceBaseUrl ?? AppConfig.apiBaseUrl).replaceAll(RegExp(r'/+$'), '');
    return WahaOrder(
      orderId: o.orderId,
      status: o.status,
      subtotal: double.parse(o.subtotalAmount),
      tax: double.parse(o.taxAmount),
      total: double.parse(o.totalAmount),
      taxRate: double.tryParse(o.taxRate),
      currency: o.currency,
      paymentReference: pay?.providerReference,
      paymentMethod: pay?.provider,
      username: o.username,
      invoiceUrl: '$base/api/invoices/${o.orderId}?offline=1',
      displayId: o.displayId,
      orderReference: o.orderReference,
      storeId: o.storeId,
      createdAt: o.createdAt,
      items: [
        for (final i in items)
          QuoteLine(
            productId: i.productId,
            name: i.nameJson == null ? const {} : (jsonDecode(i.nameJson!) as Map<String, dynamic>),
            quantity: i.quantity,
            unitPrice: double.parse(i.displayUnitPrice ?? i.unitPrice),
            lineTotal: double.parse((Dec.parse(i.lineNet) + Dec.parse(i.lineTax)).toFixed(2)),
          ),
      ],
    );
  }

  /// The body for POST /api/sync/orders (offline.md section 6).
  Future<Map<String, dynamic>> buildPushBody(String orderId) async {
    final o = await (db.select(db.localOrders)..where((t) => t.orderId.equals(orderId)))
        .getSingle();
    final items = await (db.select(db.localOrderItems)
          ..where((t) => t.orderId.equals(orderId))
          ..orderBy([(t) => OrderingTerm.asc(t.lineNo)]))
        .get();
    final pays = await (db.select(db.localPayments)
          ..where((t) => t.orderId.equals(orderId) & t.outcome.equals('PAID'))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
    num n(String s) => num.parse(s);
    return {
      'orderId': o.orderId,
      'orderReference': o.orderReference,
      'storeId': o.storeId,
      if (o.username != null) 'username': o.username,
      'status': o.status,
      'currency': o.currency,
      'taxRate': n(o.taxRate),
      'subtotalAmount': n(o.subtotalAmount),
      'taxAmount': n(o.taxAmount),
      'totalAmount': n(o.totalAmount),
      'createdAt': o.createdAt,
      'items': [
        for (final i in items)
          {
            'lineNo': i.lineNo,
            'productId': i.productId,
            'quantity': i.quantity,
            'unitPrice': n(i.unitPrice),
          }
      ],
      'payments': [for (final p in pays) _paymentJson(p)],
    };
  }
}

import 'dart:async';
import 'dart:convert';

import '../state/auth_service.dart';
import 'api_client.dart';
import 'local_prefs.dart';
import 'trace_log.dart';

/// One card approval that arrived after the kiosk had given up on the payment
/// (cancelled or timed out). The customer's card was charged, so it is kept
/// until the server has given a final answer.
class LateApproval {
  final String orderId;
  final double amount;
  final String rrn;
  final String? approvalCode;
  final String? terminalId;
  final int attempts;

  const LateApproval({
    required this.orderId,
    required this.amount,
    required this.rrn,
    this.approvalCode,
    this.terminalId,
    this.attempts = 0,
  });

  LateApproval withAttempt() => LateApproval(
        orderId: orderId,
        amount: amount,
        rrn: rrn,
        approvalCode: approvalCode,
        terminalId: terminalId,
        attempts: attempts + 1,
      );

  Map<String, dynamic> toJson() => {
        'orderId': orderId,
        'amount': amount,
        'rrn': rrn,
        if (approvalCode != null) 'approvalCode': approvalCode,
        if (terminalId != null) 'terminalId': terminalId,
        'attempts': attempts,
      };

  static LateApproval? tryParse(String raw) {
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final orderId = m['orderId'] as String?;
      final rrn = m['rrn'] as String?;
      final amount = (m['amount'] as num?)?.toDouble();
      if (orderId == null || rrn == null || rrn.isEmpty || amount == null) return null;
      return LateApproval(
        orderId: orderId,
        amount: amount,
        rrn: rrn,
        approvalCode: m['approvalCode'] as String?,
        terminalId: m['terminalId'] as String?,
        attempts: (m['attempts'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Tells the server about a card approval that came after the kiosk gave up
/// (POST /api/orders/{id}/late-approval). The server marks the order paid only
/// if it is still unpaid, young enough (its own limit, 3 minutes by default,
/// counted from order creation) and the amount matches; otherwise it answers
/// IGNORED. Both answers are final. Only a lost connection or a server error
/// is retried, a few minutes at most: after the server's limit a retry can
/// only be ignored anyway.
class LateApprovalService {
  LateApprovalService._();
  static final LateApprovalService instance = LateApprovalService._();

  /// Every 10 s, at most 40 tries (about 7 minutes): longer than the server's
  /// default limit, so an order is never given up on earlier than it must be.
  static const retryEvery = Duration(seconds: 10);
  static const maxAttempts = 40;

  ApiClient? _api;
  Timer? _timer;
  bool _busy = false;

  /// Starts the retry check. Safe to call more than once.
  void start(ApiClient api) {
    _api = api;
    _timer ??= Timer.periodic(retryEvery, (_) => unawaited(flush()));
    unawaited(flush());
  }

  /// Records the approval and tries to send it at once.
  Future<void> report({
    required String orderId,
    required double amount,
    String? rrn,
    String? approvalCode,
    String? terminalId,
  }) async {
    if (rrn == null || rrn.trim().isEmpty) {
      // The server requires the rrn; without it nothing can be reported.
      TraceLog.log('LATE APPROVAL: order $orderId, $amount — no rrn in the answer, cannot report it; reconcile by hand');
      return;
    }
    final entry = LateApproval(
      orderId: orderId,
      amount: amount,
      rrn: rrn.trim(),
      approvalCode: approvalCode,
      terminalId: terminalId,
    );
    final list = LocalPrefs.lateApprovals.toList();
    final known = list.map(LateApproval.tryParse).whereType<LateApproval>().any((e) => e.rrn == entry.rrn);
    if (!known) {
      list.add(jsonEncode(entry.toJson()));
      await LocalPrefs.setLateApprovals(list);
    }
    TraceLog.log('LATE APPROVAL: order $orderId, $amount, rrn ${entry.rrn} — reporting to the server');
    await flush();
  }

  Future<void> flush() async {
    final api = _api;
    if (api == null || _busy) return;
    final raw = LocalPrefs.lateApprovals;
    if (raw.isEmpty) return;
    _busy = true;
    try {
      final keep = <String>[];
      for (final r in raw) {
        final e = LateApproval.tryParse(r);
        if (e == null) continue;
        final next = e.withAttempt();
        final token = authService.token;
        if (token != null) {
          try {
            final result = await api.reportLateApproval(
              e.orderId,
              amount: e.amount,
              rrn: e.rrn,
              approvalCode: e.approvalCode,
              terminalId: e.terminalId,
              token: token,
            );
            TraceLog.log('LATE APPROVAL: order ${e.orderId}, rrn ${e.rrn} — server answered $result');
            if (result == 'IGNORED' || result == 'REJECTED') {
              TraceLog.log('LATE APPROVAL: order ${e.orderId} NOT marked paid but the card was charged (approval ${e.approvalCode}, rrn ${e.rrn}) — reconcile by hand');
            }
            continue; // a definite answer: done
          } catch (err) {
            TraceLog.log('LATE APPROVAL: order ${e.orderId} — could not report yet ($err), try ${next.attempts} of $maxAttempts');
          }
        }
        if (next.attempts >= maxAttempts) {
          TraceLog.log('LATE APPROVAL: order ${e.orderId}, rrn ${e.rrn} — gave up reporting; the card was charged, reconcile by hand');
          continue;
        }
        keep.add(jsonEncode(next.toJson()));
      }
      await LocalPrefs.setLateApprovals(keep);
    } finally {
      _busy = false;
    }
  }
}

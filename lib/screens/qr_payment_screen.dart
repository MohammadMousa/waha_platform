import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/order.dart';

// Shown as a Dialog (with margins) when a QR_LINK payment method is tapped.
// Shows the payment QR the customer scans on their phone. Subscribes to SSE
// on GET /api/orders/{id}/payment-events and pops with the paid WahaOrder on
// confirmation. methodLabel is shown in the header for support reference.
class QrPaymentScreen extends StatefulWidget {
  final String orderId;
  final String qrCodeDataUri; // data:image/png;base64,...
  final DateTime expiresAt;
  final String methodLabel;
  final Future<WahaOrder> Function() onRefreshOrder;

  const QrPaymentScreen({
    super.key,
    required this.orderId,
    required this.qrCodeDataUri,
    required this.expiresAt,
    required this.methodLabel,
    required this.onRefreshOrder,
  });

  @override
  State<QrPaymentScreen> createState() => _QrPaymentScreenState();
}

enum _QrPhase { waiting, confirmed, expired }

class _QrPaymentScreenState extends State<QrPaymentScreen> {
  _QrPhase _phase = _QrPhase.waiting;
  Timer? _countdownTimer;
  Duration _remaining = Duration.zero;
  http.Client? _sseClient;
  StreamSubscription<String>? _sseSub;

  @override
  void initState() {
    super.initState();
    _remaining = widget.expiresAt.difference(DateTime.now());
    if (_remaining.isNegative) {
      _phase = _QrPhase.expired;
    } else {
      _startCountdown();
      _subscribeToSse();
    }
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final rem = widget.expiresAt.difference(DateTime.now());
      if (!mounted) return;
      if (rem.isNegative) {
        _countdownTimer?.cancel();
        if (_phase == _QrPhase.waiting) setState(() => _phase = _QrPhase.expired);
      } else {
        setState(() => _remaining = rem);
      }
    });
  }

  void _subscribeToSse() {
    final client = http.Client();
    _sseClient = client;
    final uri = Uri.parse(
        '${AppConfig.apiBaseUrl}/api/orders/${widget.orderId}/payment-events');
    final request = http.Request('GET', uri)
      ..headers['Accept'] = 'text/event-stream'
      ..headers['Cache-Control'] = 'no-cache';

    client.send(request).then((response) {
      _sseSub = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            _onSseLine,
            onError: (_) { _handleSseError(); },
            onDone: _handleSseDone,
          );
    }).catchError((_) { _handleSseError(); });
  }

  void _onSseLine(String line) {
    if (line.startsWith('data:') && line.contains('PAID')) {
      _onPaymentConfirmed();
    }
  }

  void _handleSseError() {
    widget.onRefreshOrder().then((order) {
      if (order.status == 'PAID' && mounted) _onPaymentConfirmedWithOrder(order);
    }).catchError((_) {});
  }

  void _handleSseDone() {
    if (_phase == _QrPhase.waiting) {
      widget.onRefreshOrder().then((order) {
        if (order.status == 'PAID' && mounted) _onPaymentConfirmedWithOrder(order);
      }).catchError((_) {});
    }
  }

  void _onPaymentConfirmed() {
    widget.onRefreshOrder().then((order) {
      if (mounted) _onPaymentConfirmedWithOrder(order);
    }).catchError((_) {
      if (mounted) setState(() => _phase = _QrPhase.confirmed);
    });
  }

  void _onPaymentConfirmedWithOrder(WahaOrder order) {
    _cancelSse();
    _countdownTimer?.cancel();
    setState(() => _phase = _QrPhase.confirmed);
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) Navigator.of(context).pop(order);
    });
  }

  void _cancelSse() {
    _sseSub?.cancel();
    _sseClient?.close();
    _sseSub = null;
    _sseClient = null;
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _cancelSse();
    super.dispose();
  }

  String _fmt2(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header row
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.methodLabel,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700)),
                    Text(l10n.qrPayTitle,
                        style: TextStyle(
                            fontSize: 13, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: _phase == _QrPhase.waiting
                    ? _showCancelConfirm
                    : () => Navigator.of(context).pop(null),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Body
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.72,
          ),
          child: SingleChildScrollView(
            child: _body(l10n, scheme),
          ),
        ),
      ],
    );
  }

  Widget _body(AppLocalizations l10n, ColorScheme scheme) {
    return switch (_phase) {
      _QrPhase.waiting => _waitingBody(l10n, scheme),
      _QrPhase.confirmed => _confirmedBody(l10n, scheme),
      _QrPhase.expired => _expiredBody(l10n),
    };
  }

  Widget _waitingBody(AppLocalizations l10n, ColorScheme scheme) {
    final mins = _fmt2(_remaining.inMinutes);
    final secs = _fmt2(_remaining.inSeconds % 60);
    final qrBytes = base64.decode(
        widget.qrCodeDataUri.replaceFirst('data:image/png;base64,', ''));

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.qrPayInstruction,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            padding: const EdgeInsets.all(12),
            child: Image.memory(qrBytes, width: 200, height: 200),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.qrPayExpiresIn(mins, secs),
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.5)),
              const SizedBox(width: 8),
              Text(l10n.qrPayWaiting,
                  style: TextStyle(
                      color: scheme.onSurfaceVariant, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: _showCancelConfirm,
            child: Text(l10n.qrPayCancel),
          ),
        ],
      ),
    );
  }

  Widget _confirmedBody(AppLocalizations l10n, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline, size: 64, color: scheme.primary),
          const SizedBox(height: 12),
          Text(l10n.qrPayConfirmed,
              style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    );
  }

  Widget _expiredBody(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_off_outlined, size: 52),
          const SizedBox(height: 12),
          Text(l10n.qrPayExpired,
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(l10n.qrPayExpiredBody,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: Text(l10n.qrPayGoBack),
          ),
        ],
      ),
    );
  }

  void _showCancelConfirm() {
    final l10n = AppLocalizations.of(context)!;
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.qrPayCancel),
        content: Text(l10n.qrPayCancelConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.qrPayCancelContinue),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop(true);
              Navigator.of(context).pop(null);
            },
            child: Text(l10n.qrPayGoBack),
          ),
        ],
      ),
    );
  }
}

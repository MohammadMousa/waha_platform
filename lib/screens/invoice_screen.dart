import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/order.dart';
import '../models/payment_method.dart';
import '../router/app_router.dart';
import '../services/api_client.dart';
import '../state/auth_service.dart';
import '../state/browsing_mode_service.dart';
import '../state/locale_service.dart';
import '../state/order_flow_controller.dart';
import '../state/store_config_service.dart';
import '../utils/locale_name.dart';
import 'qr_payment_screen.dart';

enum _Phase { loading, loaded, paying, waiting, paid, cancelled }

class InvoiceScreen extends StatefulWidget {
  final String orderId;
  const InvoiceScreen({super.key, required this.orderId});

  @override
  State<InvoiceScreen> createState() => _InvoiceScreenState();
}

class _InvoiceScreenState extends State<InvoiceScreen> {
  _Phase _phase = _Phase.loading;
  WahaOrder? _order;
  String? _error;

  List<PaymentMethod> _methods = [];
  bool _declined = false;
  String? _declineDetail;
  bool _launchingSession = false;
  String? _sessionError;

  Timer? _pollTimer;
  int _pollAttempts = 0;
  static const _maxPollAttempts = 150; // ~5 min at 2s


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadOrder());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadOrder() async {
    setState(() {
      _phase = _Phase.loading;
      _error = null;
    });
    try {
      final order =
          await context.read<ApiClient>().getOrder(widget.orderId);
      if (!mounted) return;
      _order = order;
      if (order.status == 'PAID') {
        _onPaid(order);
      } else if (order.status == 'CANCELLED') {
        if (mounted) setState(() => _phase = _Phase.cancelled);
      } else if (order.status == 'PENDING') {
        // Payment session already started in a previous screen visit — resume polling.
        if (mounted) {
          setState(() => _phase = _Phase.waiting);
          _pollAttempts = 0;
          _pollTimer =
              Timer.periodic(const Duration(seconds: 2), (_) => _pollOnce());
        }
      } else {
        await _loadMethods();
        if (mounted) setState(() => _phase = _Phase.loaded);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _loadMethods() async {
    try {
      final mode = browsingModeService.mode.name.toUpperCase();
      final storeId =
          authService.sessionStoreId ?? storeConfigService.storeId;
      _methods = await context
          .read<ApiClient>()
          .getPaymentMethods(mode: mode, storeId: storeId);
    } catch (_) {
      // Show methods as empty — user will see "no methods" state
    }
  }

  void _onPaid(WahaOrder order) {
    _order = order;
    setState(() => _phase = _Phase.paid);
    if (browsingModeService.mode == BrowsingMode.kiosk) {
      // Delay one frame so the Scaffold beneath the dialog is fully built.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          barrierColor: Colors.black87,
          builder: (_) => _KioskPaidDialog(
            order: order,
            onNewOrder: _resetAndGoHome,
          ),
        );
      });
    }
  }

  void _resetAndGoHome() {
    context.read<OrderFlowController>().reset();
    if (mounted) {
      Navigator.of(context)
          .pushNamedAndRemoveUntil(Routes.landing, (r) => false);
    }
  }

  // ── Simulated payment ────────────────────────────────────────────────────────

  Future<void> _paySimulated({required String outcome}) async {
    if (_phase == _Phase.paying) return;
    setState(() {
      _phase = _Phase.paying;
      _declined = false;
    });
    final flow = context.read<OrderFlowController>();
    try {
      final result = await flow.pay(simulateOutcome: outcome);
      if (!mounted) return;
      if (result.paid) {
        _onPaid(result.order);
      } else {
        setState(() {
          _phase = _Phase.loaded;
          _declined = true;
          _declineDetail = result.detail;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _phase = _Phase.loaded);
    }
  }

  // ── Redirect / QR payment ────────────────────────────────────────────────────

  Future<void> _payWithRedirect(PaymentMethod method) async {
    // Guard against double-tap: the onTap closure captures _launchingSession at
    // build time, so a second tap before the rebuild sees the old false value.
    // Reading the live field here (single-threaded Dart) catches it.
    if (_launchingSession) return;
    setState(() {
      _launchingSession = true;
      _sessionError = null;
    });
    final flow = context.read<OrderFlowController>();
    try {
      final session = await flow.createPaymentSession(
          provider: method.key, providerMode: method.provider);

      if (!mounted) return;

      if (method.isQrLink) {
        setState(() => _launchingSession = false);
        final lang = localeService.locale.languageCode;
        final methodLabel = localeName(method.displayName, lang)
            .let((s) => s.isEmpty ? method.key : s);
        final paidOrder = await showDialog<WahaOrder>(
          context: context,
          barrierDismissible: false,
          builder: (_) => Dialog(
            insetPadding: const EdgeInsets.symmetric(
                horizontal: 24, vertical: 48),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            child: QrPaymentScreen(
              orderId: flow.orderId!,
              qrCodeDataUri: session.qrCodeDataUri!,
              expiresAt: session.expiresAt!,
              methodLabel: methodLabel,
              onRefreshOrder: flow.refreshOrder,
            ),
          ),
        );
        if (!mounted) return;
        if (paidOrder != null) _onPaid(paidOrder);
        return;
      }

      // PAYMENT_URL: no backend session needed — QR is the invoice URL.
      // Should not reach here since _handlePaymentUrl is called directly,
      // but guard for safety.
      if (method.isPaymentUrl) {
        setState(() => _launchingSession = false);
        return;
      }

      // Standard browser redirect flow (REDIRECT provider)
      final launched = await launchUrl(
          Uri.parse(session.redirectUrl),
          mode: LaunchMode.externalApplication);
      if (!launched) throw Exception('launch failed');
      if (!mounted) return;
      setState(() {
        _launchingSession = false;
        _phase = _Phase.waiting;
      });
      _pollAttempts = 0;
      _pollTimer =
          Timer.periodic(const Duration(seconds: 2), (_) => _pollOnce());
    } catch (e) {
      if (mounted) {
        setState(() {
          _launchingSession = false;
          _sessionError = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _pollOnce() async {
    _pollAttempts++;
    final flow = context.read<OrderFlowController>();
    try {
      final order = await flow.refreshOrder();
      if (order.status == 'PAID') {
        _pollTimer?.cancel();
        if (mounted) _onPaid(order);
        return;
      }
    } catch (_) {}
    if (_pollAttempts >= _maxPollAttempts && mounted) {
      _pollTimer?.cancel();
      setState(() => _phase = _Phase.loaded);
    }
  }

  void _cancelWaiting() {
    _pollTimer?.cancel();
    setState(() => _phase = _Phase.loaded);
  }

  void _shareInvoice(WahaOrder order) {
    final url = order.invoiceUrl ??
        Uri.base.resolve('#/invoice/${order.orderId}').toString();
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 16, 24, MediaQuery.of(ctx).padding.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(l10n.shareInvoice,
                style: Theme.of(ctx)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            _ShareOption(
              icon: Icons.chat_outlined,
              label: 'WhatsApp',
              color: const Color(0xFF25D366),
              onTap: () async {
                Navigator.of(ctx).pop();
                final waUrl = Uri.parse(
                    'https://wa.me/?text=${Uri.encodeComponent(url)}');
                await launchUrl(waUrl,
                    mode: LaunchMode.externalApplication);
              },
            ),
            const SizedBox(height: 8),
            _ShareOption(
              icon: Icons.send_outlined,
              label: 'Telegram',
              color: const Color(0xFF2AABEE),
              onTap: () async {
                Navigator.of(ctx).pop();
                final tgUrl = Uri.parse(
                    'https://t.me/share/url?url=${Uri.encodeComponent(url)}');
                await launchUrl(tgUrl,
                    mode: LaunchMode.externalApplication);
              },
            ),
            const SizedBox(height: 8),
            _ShareOption(
              icon: Icons.copy_outlined,
              label: l10n.shareCopyLink,
              color: scheme.outline,
              onTap: () {
                Clipboard.setData(ClipboardData(text: url));
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(l10n.shareLinkCopied),
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _handleMethod(PaymentMethod method) {
    if (method.provider == 'SIMULATED') {
      _paySimulated(outcome: 'SUCCESS');
    } else if (method.isPaymentUrl) {
      _handlePaymentUrl(method);
    } else {
      _payWithRedirect(method);
    }
  }

  // PAYMENT_URL: construct invoice URL from paymentUrl template + orderId,
  // show as QR dialog. Customer scans on phone, pays there. Kiosk polls.
  Future<void> _handlePaymentUrl(PaymentMethod method) async {
    final baseUrl = method.paymentUrl;
    final orderId = _order?.orderId;
    if (baseUrl == null || baseUrl.isEmpty || orderId == null) {
      setState(() => _sessionError = 'Mobile Payment is not configured for this store.');
      return;
    }
    final qrUrl = '$baseUrl/invoice/$orderId';
    final lang = localeService.locale.languageCode;
    final methodLabel = localeName(method.displayName, lang)
        .let((s) => s.isEmpty ? method.key : s);
    final l10n = AppLocalizations.of(context)!;
    final flow = context.read<OrderFlowController>();

    final paidOrder = await showDialog<WahaOrder>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: _MobilePaymentScreen(
          qrUrl: qrUrl,
          methodLabel: methodLabel,
          scanHint: l10n.mobilePaymentScanHint,
          pollingLabel: l10n.mobilePaymentPolling,
          onRefreshOrder: flow.refreshOrder,
        ),
      ),
    );
    if (!mounted) return;
    if (paidOrder != null) _onPaid(paidOrder);
  }

  // ── Payment method popup ──────────────────────────────────────────────────────

  void _showPaymentSheet(PaymentMethod method) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final lang = localeService.locale.languageCode;
    final label = localeName(method.displayName, lang)
        .let((s) => s.isEmpty ? method.key : s);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            CircleAvatar(
              radius: 28,
              backgroundColor: scheme.primaryContainer,
              child: Icon(_iconForMethod(method),
                  color: scheme.onPrimaryContainer, size: 28),
            ),
            const SizedBox(height: 12),
            Text(label,
                style: Theme.of(ctx)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            if (method.provider == 'REDIRECT') ...[
              const SizedBox(height: 8),
              Text(
                l10n.payOpenedBrowser,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.outline, fontSize: 13),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _handleMethod(method);
                },
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: Text(l10n.payConfirm,
                    style: const TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconForMethod(PaymentMethod method) {
    if (method.isPaymentUrl) return Icons.phone_android_outlined;
    return switch (method.key.replaceAll('_qr', '')) {
      'simulated' => Icons.phone_android_outlined,
      'stripe' => Icons.credit_card,
      'myfatoorah' => Icons.account_balance_outlined,
      _ => (method.provider == 'REDIRECT' || method.provider == 'QR_LINK')
          ? Icons.qr_code_outlined
          : Icons.payment_outlined,
    };
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    // Block back in kiosk/shopping — these are self-service modes with no
    // meaningful "previous screen" to return to. Normal mode always allows back.
    final bool isKiosk = browsingModeService.mode == BrowsingMode.kiosk;
    final bool isShopping = browsingModeService.mode == BrowsingMode.shopping;
    final bool blockBack = isKiosk || isShopping;

    return PopScope(
      canPop: !blockBack,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.invoiceTitle),
          leading: blockBack ? null : const BackButton(),
          automaticallyImplyLeading: false,
          actions: blockBack
              ? [
                  TextButton(
                    onPressed: _resetAndGoHome,
                    child: Text(l10n.invoiceNewOrder),
                  ),
                  const SizedBox(width: 8),
                ]
              : null,
        ),
        body: switch (_phase) {
        _Phase.loading => _error != null
            ? _buildError(l10n)
            : const Center(child: CircularProgressIndicator()),
        _Phase.loaded => _buildInvoice(l10n),
        _Phase.paying =>
          const Center(child: CircularProgressIndicator()),
        _Phase.waiting => _buildWaiting(l10n),
        _Phase.paid => _buildPaid(l10n),
        _Phase.cancelled => _buildCancelled(l10n),
      },
      ),
    );
  }

  Widget _buildError(AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 56),
            const SizedBox(height: 16),
            Text(_error ?? 'Error', textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton(onPressed: _loadOrder, child: Text(l10n.browseRetry)),
          ],
        ),
      ),
    );
  }

  Widget _buildCancelled(AppLocalizations l10n) {
    final order = _order;
    final scheme = Theme.of(context).colorScheme;
    final currency = storeConfigService.storeCurrency ?? order?.currency;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.errorContainer.withOpacity(0.4),
            ),
            child: Icon(Icons.cancel_outlined, color: scheme.error, size: 56),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.invoiceCancelled,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: scheme.error,
                ),
          ),
          if (order != null) ...[
            const SizedBox(height: 8),
            Text(
              order.displayId != null
                  ? '${l10n.invoiceOrderNum} #${order.displayId}'
                  : order.orderId.substring(0, 8),
              style: TextStyle(color: scheme.outline),
            ),
            const SizedBox(height: 24),
            _InvoiceHeaderCard(order: order, currency: currency, l10n: l10n),
            const SizedBox(height: 16),
            _CollapsibleItems(order: order, currency: currency, l10n: l10n),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _resetAndGoHome,
              child: Text(l10n.invoiceNewOrder),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInvoice(AppLocalizations l10n) {
    final order = _order;
    if (order == null) return const Center(child: CircularProgressIndicator());
    final scheme = Theme.of(context).colorScheme;
    final lang = localeService.locale.languageCode;
    final currency = storeConfigService.storeCurrency ?? order.currency;
    final isNormal = browsingModeService.mode == BrowsingMode.normal;
    final isKiosk = browsingModeService.mode == BrowsingMode.kiosk;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Invoice header card
          _InvoiceHeaderCard(order: order, currency: currency, l10n: l10n),
          const SizedBox(height: 16),

          // Errors
          if (_declined) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.cancel_outlined, color: scheme.onErrorContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _declineDetail ?? l10n.paymentDeclined,
                      style: TextStyle(color: scheme.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_sessionError != null) ...[
            Text(_sessionError!,
                style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
          ],

          // Payment method selection label
          Text(
            l10n.invoiceSelectPayment,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),

          // Payment method grid
          if (_methods.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(l10n.payNoMethods,
                    style: TextStyle(color: scheme.outline)),
              ),
            )
          else
            Center(
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  for (final method in _methods)
                    _PayMethodChip(
                      method: method,
                      icon: _iconForMethod(method),
                      label: localeName(method.displayName, lang)
                          .let((s) => s.isEmpty ? method.key : s),
                      onTap: _launchingSession
                          ? null
                          : () {
                              if (method.isPaymentUrl) {
                                _handlePaymentUrl(method);
                              } else if (method.provider == 'REDIRECT' ||
                                  method.provider == 'QR_LINK') {
                                _payWithRedirect(method);
                              } else {
                                _showPaymentSheet(method);
                              }
                            },
                    ),
                ],
              ),
            ),

          const SizedBox(height: 24),

          // Collapsible items
          _CollapsibleItems(order: order, currency: currency, l10n: l10n),

          // Share row — hidden in kiosk (QR is in the header card)
          if (!isKiosk && isNormal) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.share_outlined),
              label: Text(l10n.shareInvoice),
              onPressed: () => _shareInvoice(order),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWaiting(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(l10n.payWaiting, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(
              l10n.payOpenedBrowser,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.outline),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: _pollOnce,
              child: Text(l10n.payCheckNow),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: _cancelWaiting, child: const Text('Cancel')),
          ],
        ),
      ),
    );
  }

  Widget _buildPaid(AppLocalizations l10n) {
    final order = _order;
    final scheme = Theme.of(context).colorScheme;
    final currency =
        storeConfigService.storeCurrency ?? order?.currency;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Big paid checkmark
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.green.shade50,
            ),
            child: const Icon(Icons.check_circle_rounded,
                color: Colors.green, size: 64),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.invoicePaid,
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: Colors.green.shade700,
                ),
          ),
          if (order != null) ...[
            const SizedBox(height: 8),
            Text(
              order.displayId != null
                  ? '${l10n.invoiceOrderNum} #${order.displayId}'
                  : order.orderId.substring(0, 8),
              style: TextStyle(color: scheme.outline),
            ),
            const SizedBox(height: 24),
            _InvoiceHeaderCard(
              order: order,
              currency: currency,
              l10n: l10n,
              showStatusBadge: false,
            ),
            const SizedBox(height: 16),
            _CollapsibleItems(order: order, currency: currency, l10n: l10n),

          ],

          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _resetAndGoHome,
              child: Text(l10n.invoiceNewOrder),
            ),
          ),
          if (order != null && browsingModeService.mode == BrowsingMode.normal) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.share_outlined),
              label: Text(l10n.shareInvoice),
              onPressed: () => _shareInvoice(order),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Kiosk paid dialog ────────────────────────────────────────────────────────
// Blocking full-screen overlay shown immediately after payment in kiosk mode.
// The customer scans the QR to get their e-invoice. Timer auto-resets to home.
// "Give me more time" restarts the countdown. Back button is disabled.

class _KioskPaidDialog extends StatefulWidget {
  final WahaOrder order;
  final VoidCallback onNewOrder;

  const _KioskPaidDialog({required this.order, required this.onNewOrder});

  @override
  State<_KioskPaidDialog> createState() => _KioskPaidDialogState();
}

class _KioskPaidDialogState extends State<_KioskPaidDialog> {
  late int _secondsLeft;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _secondsLeft = kioskTimerConfig.afterInvoiceWarningCountdown.inSeconds;
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        _timer?.cancel();
        _doNewOrder();
      }
    });
  }

  void _resetTimer() {
    setState(() {
      _secondsLeft = kioskTimerConfig.afterInvoiceWarningCountdown.inSeconds;
    });
    _startTimer();
  }

  void _doNewOrder() {
    _timer?.cancel();
    if (mounted) Navigator.of(context).pop();
    widget.onNewOrder();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final url = widget.order.invoiceUrl;

    return PopScope(
      canPop: false,
      child: Dialog.fullscreen(
        backgroundColor: Colors.black87,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // PAID stamp
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.green.shade600,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.withOpacity(0.4),
                        blurRadius: 32,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.check_rounded,
                      color: Colors.white, size: 62),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.kioskPaidTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 32),

                // QR section
                if (url != null) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: QrImageView(
                      data: url,
                      version: QrVersions.auto,
                      size: 200,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.kioskPaidScanHint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 15),
                  ),
                  const SizedBox(height: 24),
                ],

                // Countdown
                Text(
                  l10n.kioskPaidClosingIn(_secondsLeft),
                  style: TextStyle(
                    color: _secondsLeft <= 5
                        ? Colors.red.shade300
                        : Colors.white54,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 32),

                // Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Colors.white30),
                          padding:
                              const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _resetTimer,
                        child: Text(l10n.kioskPaidResetTimer),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: scheme.primary,
                          padding:
                              const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _doNewOrder,
                        child: Text(
                          l10n.kioskPaidNewOrder,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Invoice header card ───────────────────────────────────────────────────────

class _InvoiceHeaderCard extends StatelessWidget {
  final WahaOrder order;
  final String? currency;
  final AppLocalizations l10n;
  final bool showStatusBadge;

  const _InvoiceHeaderCard({
    required this.order,
    required this.currency,
    required this.l10n,
    this.showStatusBadge = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color statusColor;
    final String statusLabel;
    switch (order.status) {
      case 'PAID':
        statusColor = Colors.green;
        statusLabel = l10n.invoicePaid;
      case 'PENDING':
        statusColor = Colors.orange;
        statusLabel = l10n.invoicePending;
      case 'CANCELLED':
        statusColor = scheme.outline;
        statusLabel = l10n.invoiceCancelled;
      default:
        statusColor = scheme.error;
        statusLabel = l10n.invoiceUnpaid;
    }

    final isKiosk = browsingModeService.mode == BrowsingMode.kiosk;
    final isNormal = browsingModeService.mode == BrowsingMode.normal;
    final lang = localeService.locale.languageCode;

    // Side widget: QR in kiosk, download icon button in normal mode.
    Widget? sideWidget;
    if (isKiosk && order.invoiceUrl != null) {
      sideWidget = Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.all(4),
        child: QrImageView(
          data: order.invoiceUrl!,
          version: QrVersions.auto,
          size: 82,
        ),
      );
    } else if (isNormal && order.invoiceUrl != null) {
      sideWidget = IconButton.outlined(
        icon: const Icon(Icons.download_outlined),
        iconSize: 28,
        tooltip: l10n.invoiceDownloadPdf,
        onPressed: () async {
          final pdfUri = Uri.parse('${order.invoiceUrl}/pdf?lang=$lang');
          await launchUrl(pdfUri, mode: LaunchMode.externalApplication);
        },
      );
    }

    return Card(
      elevation: 0,
      color: scheme.primaryContainer.withOpacity(0.3),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info column
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Order number + status badge
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: order.displayId != null
                            ? RichText(
                                text: TextSpan(
                                  style: DefaultTextStyle.of(context).style,
                                  children: [
                                    TextSpan(
                                      text: '${l10n.invoiceOrderNum}  ',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: scheme.outline),
                                    ),
                                    TextSpan(
                                      text: '#${order.displayId}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(fontWeight: FontWeight.w700),
                                    ),
                                  ],
                                ),
                              )
                            : Text(
                                '#${order.orderId.substring(0, 8).toUpperCase()}',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                      ),
                      if (showStatusBadge) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            statusLabel,
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (order.createdAt != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _formatDate(order.createdAt!),
                      style: TextStyle(color: scheme.outline, fontSize: 13),
                    ),
                  ],
                  const SizedBox(height: 10),
                  // Total — small label above the Due amount
                  Row(
                    children: [
                      Text(
                        '${l10n.cartTotal}: ',
                        style: TextStyle(fontSize: 12, color: scheme.outline),
                      ),
                      Text(
                        _formatPrice(order.total, currency),
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.outline,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Due label
                  Text(
                    l10n.invoiceDueLabel,
                    style: TextStyle(fontSize: 12, color: scheme.outline),
                  ),
                  // Due value — big, primary color
                  Builder(builder: (context) {
                    final due = order.status == 'PAID' ? 0.0 : order.total;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          due.toStringAsFixed(2),
                          style: Theme.of(context)
                              .textTheme
                              .displaySmall
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: scheme.primary,
                                height: 1.1,
                              ),
                        ),
                        if (currency != null) ...[
                          const SizedBox(width: 5),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              _currencySymbol(currency),
                              style: TextStyle(
                                fontSize: 14,
                                color: scheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    );
                  }),
                  if (order.status == 'PAID' &&
                      order.paymentMethod != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      l10n.invoicePaidVia(
                          _displayMethod(order.paymentMethod!)),
                      style: TextStyle(
                        color: Colors.green.shade700,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Side widget (QR or download)
            if (sideWidget != null) ...[
              const SizedBox(width: 12),
              sideWidget,
            ],
          ],
        ),
      ),
    );
  }
}

String _displayMethod(String key) {
  switch (key.toLowerCase()) {
    case 'stripe':
      return 'Stripe';
    case 'myfatoorah':
      return 'MyFatoorah';
    case 'simulated':
      return 'Terminal';
    default:
      return key;
  }
}

// ── Collapsible items section ─────────────────────────────────────────────────

class _CollapsibleItems extends StatefulWidget {
  final WahaOrder order;
  final String? currency;
  final AppLocalizations l10n;

  const _CollapsibleItems(
      {required this.order, required this.currency, required this.l10n});

  @override
  State<_CollapsibleItems> createState() => _CollapsibleItemsState();
}

class _CollapsibleItemsState extends State<_CollapsibleItems> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = widget.l10n;
    final lang = localeService.locale.languageCode;

    return Card(
      elevation: 0,
      color: scheme.surfaceVariant.withOpacity(0.4),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(Icons.receipt_long_outlined,
                      size: 20, color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.invoiceItems,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    '${widget.order.items.length}',
                    style: TextStyle(color: scheme.outline, fontSize: 13),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                    color: scheme.outline,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            for (final item in widget.order.items)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        localeName(item.name, lang)
                            .let((s) => s.isEmpty ? item.name.toString() : s),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    Text(
                      '×${item.quantity}',
                      style: TextStyle(
                          color: scheme.outline, fontSize: 13),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _formatPrice(item.lineTotal, widget.currency),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                children: [
                  _SummaryRow(
                    label: l10n.cartSubtotal,
                    value: _formatPrice(widget.order.subtotal, widget.currency),
                    scheme: scheme,
                  ),
                  const SizedBox(height: 4),
                  _SummaryRow(
                    label: l10n.cartTax,
                    value: _formatPrice(widget.order.tax, widget.currency),
                    scheme: scheme,
                  ),
                  const Divider(height: 16),
                  _SummaryRow(
                    label: l10n.cartTotal,
                    value: _formatPrice(widget.order.total, widget.currency),
                    scheme: scheme,
                    bold: true,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Payment method chip ───────────────────────────────────────────────────────

class _PayMethodChip extends StatelessWidget {
  final PaymentMethod method;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _PayMethodChip({
    required this.method,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 110,
      height: 88,
      child: Material(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: scheme.onPrimaryContainer, size: 28),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.onPrimaryContainer,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Summary row (subtotal / tax / total) ─────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final ColorScheme scheme;
  final bool bold;

  const _SummaryRow({
    required this.label,
    required this.value,
    required this.scheme,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label,
            style: TextStyle(
              color: bold ? scheme.onSurface : scheme.outline,
              fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
              fontSize: bold ? 14 : 13,
            )),
        const Spacer(),
        Text(value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              fontSize: bold ? 14 : 13,
              color: bold ? scheme.primary : scheme.onSurface,
            )),
      ],
    );
  }
}

// ── Share option row ─────────────────────────────────────────────────────────

class _ShareOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ShareOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 16),
            Text(label,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _formatPrice(double amount, String? currency) {
  final formatted = amount.toStringAsFixed(2);
  if (currency == null) return formatted;
  final upper = currency.toUpperCase();
  if (upper == 'SAR') return '$formatted ﷼';
  if (upper == 'USD') return '\$$formatted';
  if (upper == 'EUR') return '€$formatted';
  return '$formatted $currency';
}

String _currencySymbol(String? currency) {
  if (currency == null) return '';

  switch (currency.toUpperCase()) {
    case 'SAR':
      return '﷼';
    case 'USD':
      return '\$';
    case 'EUR':
      return '€';
    default:
      return currency;
  }
}

String _formatDate(String iso) {
  try {
    final dt = DateTime.parse(iso).toLocal();
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  } catch (_) {
    return iso;
  }
}

extension _StringX on String {
  String let(String Function(String) fn) => fn(this);
}

// ── Mobile Payment QR Screen ──────────────────────────────────────────────────
// Dialog content for PAYMENT_URL provider. Shows the invoice URL as a QR so
// the kiosk customer can scan it and pay on their own phone. Polls the order
// status until PAID, then pops with the paid order.

class _MobilePaymentScreen extends StatefulWidget {
  final String qrUrl;
  final String methodLabel;
  final String scanHint;
  final String pollingLabel;
  final Future<WahaOrder> Function() onRefreshOrder;

  const _MobilePaymentScreen({
    required this.qrUrl,
    required this.methodLabel,
    required this.scanHint,
    required this.pollingLabel,
    required this.onRefreshOrder,
  });

  @override
  State<_MobilePaymentScreen> createState() => _MobilePaymentScreenState();
}

class _MobilePaymentScreenState extends State<_MobilePaymentScreen> {
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _poll() {
    widget.onRefreshOrder().then((order) {
      if (order.status == 'PAID' && mounted) {
        _pollTimer?.cancel();
        Navigator.of(context).pop(order);
      }
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.methodLabel,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    Text(widget.scanHint,
                        style: TextStyle(
                            fontSize: 13, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(null),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                child: QrImageView(
                  data: widget.qrUrl,
                  version: QrVersions.auto,
                  size: 200,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                  const SizedBox(width: 8),
                  Text(widget.pollingLabel,
                      style: TextStyle(
                          color: scheme.onSurfaceVariant, fontSize: 13)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

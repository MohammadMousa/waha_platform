import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/order.dart';
import '../models/payment_method.dart';
import '../models/terminal_session.dart';
import '../router/app_router.dart';
import '../services/api_client.dart';
import '../services/geidea_terminal_bridge.dart';
import '../services/local_prefs.dart';
import '../state/auth_service.dart';
import '../state/browsing_mode_service.dart';
import '../state/locale_service.dart';
import '../state/order_flow_controller.dart';
import '../services/trace_log.dart';
import '../state/store_config_service.dart';
import '../utils/locale_name.dart';
import '../widgets/timer_footer_sheet.dart';
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

  // Cached in initState, not read fresh in dispose() — same pattern
  // KioskIdleGuard already uses safely; calling context.read() for the
  // first time inside dispose() risks throwing if the element's ancestor
  // chain has already started tearing down by then.
  late final OrderFlowController _flow;

  List<PaymentMethod> _methods = [];
  bool _declined = false;
  String? _declineDetail;
  bool _launchingSession = false;
  String? _sessionError;

  Timer? _pollTimer;
  int _pollAttempts = 0;
  static const _maxPollAttempts = 150; // ~5 min at 2s

  // Auto-select/auto-pick — a convenience for the first few seconds after
  // the screen loads, NOT a way out of this screen: sitting idle here is
  // handled by the single app-wide KioskIdleGuard (see app_router.dart).
  // Armed only on the initial load (see _loadOrder); a decline or a
  // cancelled redirect returning to _Phase.loaded does NOT re-arm it, so a
  // customer is never silently re-charged after backing out once, and never
  // auto-picked into a second attempt either:
  //  - Exactly one method: auto-select it after a short delay — skips the
  //    pointless extra tap.
  //  - More than one: auto-pick after a longer delay if the customer
  //    hasn't chosen manually — `terminal` if it's an active method for
  //    this store (the physical kiosk's expected common case), otherwise
  //    just the first listed method. This is a config check (is `terminal`
  //    in `_methods`), not a live hardware ping — if the hardware itself
  //    turns out not to work, _handleTerminal's own failed/retry state
  //    handles that already, same as a manual pick would.
  //  - Zero methods (e.g. a transient getPaymentMethods() failure): nothing
  //    to pick, so nothing is armed — the idle guard resets the session.
  static const _autoSelectDelaySeconds = 4;
  static const _autoPickDelaySeconds = 5;
  Timer? _autoSelectTimer;
  int? _autoSelectSecondsLeft;

  @override
  void initState() {
    super.initState();
    _flow = context.read<OrderFlowController>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadOrder());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _autoSelectTimer?.cancel();
    // Safety net: if this screen is disposed while still polling (left the
    // flow some way other than _pollOnce/_cancelWaiting reaching one of
    // their own end states), paymentInProgress would otherwise stay stuck
    // true forever, permanently blocking cart's KioskIdleGuard even after
    // leaving payment entirely.
    _flow.setPaymentInProgress(false);
    super.dispose();
  }

  void _maybeStartAutoSelect() {
    if (_methods.isEmpty) {
      TraceLog.log('Invoice: no payment methods — idle guard will reset the session');
      return;
    }
    final delay = _methods.length == 1 ? _autoSelectDelaySeconds : _autoPickDelaySeconds;
    TraceLog.log(
        'Invoice: auto-${_methods.length == 1 ? "select" : "pick"} armed, ${_methods.length} method(s), ${delay}s');
    setState(() => _autoSelectSecondsLeft = delay);
    _autoSelectTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final left = _autoSelectSecondsLeft! - 1;
      if (left <= 0) {
        _cancelAutoSelect();
        final method = _chooseAutoPickMethod();
        TraceLog.log('Invoice: auto-picked ${method.key} (${method.provider})');
        _handleMethod(method);
      } else {
        setState(() => _autoSelectSecondsLeft = left);
      }
    });
  }

  /// Only called once _methods.isNotEmpty is already established (see
  /// _maybeStartAutoSelect) — always returns a real method, never null.
  PaymentMethod _chooseAutoPickMethod() {
    for (final method in _methods) {
      if (method.provider == 'TERMINAL') return method;
    }
    return _methods.first;
  }

  void _cancelAutoSelect() {
    _autoSelectTimer?.cancel();
    _autoSelectTimer = null;
    if (mounted && _autoSelectSecondsLeft != null) {
      setState(() => _autoSelectSecondsLeft = null);
    }
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
        // Payment session already started in a previous screen visit — resume
        // polling. Same suspension as _payWithRedirect's own poll start —
        // cart's still-alive KioskIdleGuard needs to stay suspended for this
        // resumed wait too, cleared in _pollOnce/_cancelWaiting same as before.
        if (mounted) {
          setState(() => _phase = _Phase.waiting);
          _pollAttempts = 0;
          context.read<OrderFlowController>().setPaymentInProgress(true);
          _pollTimer =
              Timer.periodic(const Duration(seconds: 2), (_) => _pollOnce());
        }
      } else {
        await _loadMethods();
        if (mounted) setState(() => _phase = _Phase.loaded);
        _maybeStartAutoSelect();
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
    TraceLog.log('Invoice: order ${order.orderId} PAID via ${order.paymentMethod ?? "unknown"}');
    // Every payment path funnels through here — the single choke point to
    // keep OrderFlowController.order in sync, which KioskIdleGuard reads to
    // suspend its own timer once paid. pay()/refreshOrder() already do this
    // for simulated/redirect/QR flows; terminal payment resolves its own
    // paid order locally and never touches the controller otherwise.
    context.read<OrderFlowController>().setOrder(order);
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
      goHomeKeepingLanding(Navigator.of(context));
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
    // See _handleTerminal's identical call for why this matters: cart's
    // KioskIdleGuard is still alive underneath this screen the whole time
    // (see app_router.dart) — without suspending it, its idle countdown
    // firing mid-payment redirects home while this await is still in
    // flight, corrupting Navigator state.
    flow.setPaymentInProgress(true);
    try {
      final result = await flow.pay(simulateOutcome: outcome);
      if (!mounted) return;
      if (result.paid) {
        _onPaid(result.order);
      } else {
        TraceLog.log('Invoice: simulated payment declined: ${result.detail}');
        setState(() {
          _phase = _Phase.loaded;
          _declined = true;
          _declineDetail = result.detail;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _phase = _Phase.loaded);
    } finally {
      flow.setPaymentInProgress(false);
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
        // See _handleTerminal's comment — this dialog polls waiting on a
        // customer's own phone and can sit open for a while too.
        flow.setPaymentInProgress(true);
        final WahaOrder? paidOrder;
        try {
          paidOrder = await showDialog<WahaOrder>(
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
        } finally {
          flow.setPaymentInProgress(false);
        }
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
      // Can poll for up to _maxPollAttempts * 2s (~5 min) waiting on a
      // customer's external browser/app — see _handleTerminal's identical
      // comment for why cart's still-alive KioskIdleGuard needs suspending
      // for the whole span, not just this function call. Cleared in every
      // place polling can end: _pollOnce's paid/exhausted branches and
      // _cancelWaiting, not here — this call starts it, it doesn't own
      // when it ends.
      flow.setPaymentInProgress(true);
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
        flow.setPaymentInProgress(false);
        if (mounted) _onPaid(order);
        return;
      }
    } catch (_) {}
    if (_pollAttempts >= _maxPollAttempts && mounted) {
      _pollTimer?.cancel();
      flow.setPaymentInProgress(false);
      setState(() => _phase = _Phase.loaded);
    }
  }

  void _cancelWaiting() {
    _pollTimer?.cancel();
    context.read<OrderFlowController>().setPaymentInProgress(false);
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
    } else if (method.provider == 'TERMINAL') {
      _handleTerminal(method);
    } else if (method.isPaymentUrl) {
      _handlePaymentUrl(method);
    } else {
      _payWithRedirect(method);
    }
  }

  Future<void> _handleTerminal(PaymentMethod method) async {
    final orderId = _order?.orderId;
    if (orderId == null) return;
    final apiClient = context.read<ApiClient>();
    final flow = context.read<OrderFlowController>();

    // Tells KioskIdleGuard to suspend its own timer for as long as this
    // dialog is open — it can sit unresolved for a long time waiting on the
    // terminal, and the idle countdown firing underneath it corrupts
    // Navigator state (see OrderFlowController.paymentInProgress).
    flow.setPaymentInProgress(true);
    final WahaOrder? paidOrder;
    try {
      paidOrder = await showDialog<WahaOrder>(
        context: context,
        barrierDismissible: false,
        builder: (_) => Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: _TerminalPaymentScreen(
            orderId: orderId,
            apiClient: apiClient,
          ),
        ),
      );
    } finally {
      flow.setPaymentInProgress(false);
    }

    if (paidOrder != null && mounted) {
      _onPaid(paidOrder);
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

    // See _handleTerminal's comment — this dialog polls waiting on a
    // customer's own phone and can sit open for a while too.
    flow.setPaymentInProgress(true);
    final WahaOrder? paidOrder;
    try {
      paidOrder = await showDialog<WahaOrder>(
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
    } finally {
      flow.setPaymentInProgress(false);
    }
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
    if (method.provider == 'TERMINAL') return Icons.contactless_outlined;
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
                              _cancelAutoSelect();
                              TraceLog.log(
                                  'Invoice: manual pick ${method.key} (${method.provider})');
                              if (method.isPaymentUrl) {
                                _handlePaymentUrl(method);
                              } else if (method.provider == 'TERMINAL') {
                                _handleTerminal(method);
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
          if (_autoSelectSecondsLeft != null) ...[
            const SizedBox(height: 10),
            Center(
              child: Text(
                l10n.autoSelectingIn(_autoSelectSecondsLeft!),
                style: TextStyle(color: scheme.outline, fontSize: 13),
              ),
            ),
          ],

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
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.share_outlined),
                label: Text(l10n.shareInvoice),
                onPressed: () => _shareInvoice(order),
              ),
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
  // Always follows the "after invoice" Settings field, regardless of the
  // "Enable Idle Timers" checkbox — this redirect always fires (a paid
  // screen can't be left up forever), on whatever duration is configured
  // there. Want it shorter/longer? Change that spinner value, not this
  // toggle.
  late int _secondsLeft;
  Timer? _timer;

  int get _countdownSeconds => kioskTimerConfig.afterInvoiceWarningCountdown.inSeconds;

  @override
  void initState() {
    super.initState();
    _secondsLeft = _countdownSeconds;
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
      _secondsLeft = _countdownSeconds;
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
    final url = widget.order.invoiceUrl;

    return PopScope(
      canPop: false,
      child: Dialog.fullscreen(
        backgroundColor: Colors.black87,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
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
                                color: Colors.green.withValues(alpha: 0.4),
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
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              // Footer sheet — same visual language as the idle-warning
              // sheet, floating on the dark celebratory background instead
              // of a plain countdown line + button row.
              TimerFooterSheet(
                message: l10n.kioskPaidClosingIn(_secondsLeft),
                secondsLeft: _secondsLeft,
                primaryLabel: l10n.kioskPaidNewOrder,
                primaryColor: Colors.green.shade600,
                onPrimary: _doNewOrder,
                secondaryLabel: l10n.kioskPaidResetTimer,
                onSecondary: _resetTimer,
              ),
            ],
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

    final due = order.status == 'PAID' ? 0.0 : order.total;
    final dueColor = due > 0 ? scheme.primary : Colors.green.shade700;

    // Side widget: QR in kiosk. Everywhere else there's no QR to show, which
    // used to leave that slot blank (just a small download button, top-
    // aligned, with empty space below it) — so outside kiosk mode the Due
    // amount lives here instead, with the download button above it when
    // available. The info column below drops Due entirely in that case, so
    // its payment-method line moves up to fill the space Due used to take.
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
    } else if (!isKiosk) {
      sideWidget = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (isNormal && order.invoiceUrl != null) ...[
            IconButton.outlined(
              icon: const Icon(Icons.download_outlined),
              iconSize: 28,
              tooltip: l10n.invoiceDownloadPdf,
              onPressed: () async {
                final pdfUri = Uri.parse('${order.invoiceUrl}/pdf?lang=$lang');
                await launchUrl(pdfUri, mode: LaunchMode.externalApplication);
              },
            ),
            const SizedBox(height: 10),
          ],
          Text(
            l10n.invoiceDueLabel,
            style: TextStyle(fontSize: 12, color: scheme.outline),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                due.toStringAsFixed(2),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: dueColor,
                      height: 1.1,
                    ),
              ),
              if (currency != null) ...[
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    _currencySymbol(currency),
                    style: TextStyle(
                      fontSize: 13,
                      color: dueColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
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
                  // Due lives here only in kiosk mode — everywhere else it
                  // moved into sideWidget (see above), so paymentMethod below
                  // moves up to take its place instead of leaving a gap.
                  if (isKiosk) ...[
                    const SizedBox(height: 4),
                    Text(
                      l10n.invoiceDueLabel,
                      style: TextStyle(fontSize: 12, color: scheme.outline),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          due.toStringAsFixed(2),
                          style: Theme.of(context)
                              .textTheme
                              .displaySmall
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: dueColor,
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
                                color: dueColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
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

  // Same overall cap as the redirect flow's polling (~5 min, see
  // _maxPollAttempts): without one this dialog waits forever on a customer
  // who walked away, and the payment-in-progress flag it holds keeps the idle
  // guard suspended for good.
  static const _maxPolls = 100; // 100 x 3 s
  int _polls = 0;

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
    if (++_polls > _maxPolls) {
      _pollTimer?.cancel();
      if (mounted) Navigator.of(context).pop(null);
      return;
    }
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

// ── Terminal payment dialog ────────────────────────────────────────────────────

class _TerminalPaymentScreen extends StatefulWidget {
  final String orderId;
  final ApiClient apiClient;

  const _TerminalPaymentScreen({required this.orderId, required this.apiClient});

  @override
  State<_TerminalPaymentScreen> createState() => _TerminalPaymentScreenState();
}

// Synchronous USB flow (Geidea): create the backend session, hand the
// amount to the terminal via GeideaTerminalBridge, and act on whatever
// comes back directly — no polling. This dialog used to poll
// GET /terminal-sessions/{id} waiting for a second device (the waha_terminal
// NFC companion app) to confirm over HTTP; that app is retired, Geidea
// replaces it, and the Kiosk itself already knows the result the moment
// the SDK callback returns.
class _TerminalPaymentScreenState extends State<_TerminalPaymentScreen> {
  String? _statusLabel;
  bool _failed = false;
  TerminalSession? _session;
  bool _started = false;

  // A failed attempt (terminal not found, session couldn't start, declined)
  // used to sit here until someone tapped Close — and while this dialog is
  // open the payment-in-progress flag stays on, which suspends the idle
  // guard, so an abandoned kiosk could never recover. Close it on its own
  // after a readable delay; the invoice screen underneath is then covered by
  // the idle guard. Deliberately NOT applied to "approved but not recorded":
  // that message is for staff (the card was charged) and must stay up.
  static const _failedAutoClose = Duration(seconds: 20);
  Timer? _autoCloseTimer;

  void _scheduleAutoClose() {
    _autoCloseTimer?.cancel();
    _autoCloseTimer = Timer(_failedAutoClose, () {
      if (mounted) Navigator.pop(context, null);
    });
  }

  @override
  void dispose() {
    _autoCloseTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // l10n needs an inherited widget lookup, unavailable in initState — set
    // the initial label here instead (runs once, before the first build, so
    // a direct field write is safe with no setState needed) and kick off
    // the actual flow. Guarded so a later dependency change (e.g. locale
    // switch) can't restart it.
    if (!_started) {
      _started = true;
      _statusLabel = AppLocalizations.of(context)!.terminalConnecting;
      _run();
    }
  }

  Future<void> _run() async {
    final l10n = AppLocalizations.of(context)!;
    final bridge = GeideaTerminalBridge.instance;

    // Always actively reconnect here, unconditionally — do NOT trust
    // checkCommunication() alone first. It only reads MainActivity's last-
    // known isUsbConnected flag, set by whichever USBConnectionListener
    // callback fired last; nothing keeps it live between that callback and
    // this exact moment. A client report of the transaction never reaching
    // the physical terminal at all (no prompt, nothing) — while the app
    // still believed it was connected — matches this exactly: the cached
    // flag said true, startPurchaseTransaction() was called against a
    // connection that had actually gone stale, and Geidea's SDK failed
    // immediately, internally, before ever writing anything to the
    // terminal for the customer to see. Forcing a fresh reconnect attempt
    // right here, every time, closes that gap — costs a few seconds, but
    // only at the one moment a stale "yes" would otherwise silently fail
    // the whole transaction with no card ever presented.
    TraceLog.log('Terminal: payment run start, order ${widget.orderId}');
    final connected = await bridge.detectTerminal(source: 'payment');
    if (!mounted) return;
    if (!connected) {
      TraceLog.log('Terminal: not connected after reconnect attempt, aborting before charging');
      setState(() {
        _failed = true;
        _statusLabel = l10n.terminalNotConnected;
      });
      _scheduleAutoClose();
      return;
    }

    final TerminalSession session;
    try {
      session = await widget.apiClient.createTerminalSession(widget.orderId);
    } catch (e) {
      TraceLog.log('Terminal: backend session create failed: $e');
      if (mounted) {
        setState(() {
          _failed = true;
          _statusLabel = l10n.terminalSessionStartFailed(e.toString());
        });
        _scheduleAutoClose();
      }
      return;
    }
    if (!mounted) return;
    TraceLog.log('Terminal: session ${session.id} created, amount ${session.amount}, prompting card');
    setState(() {
      _session = session;
      _statusLabel = l10n.terminalSwipeCard;
    });

    final result = await bridge.startPayment(
      amount: session.amount,
      reference: session.orderId,
      timeout: Duration(seconds: LocalPrefs.terminalTimeoutSeconds),
    );
    if (!mounted) return;
    TraceLog.log('Terminal: SDK result approved=${result.approved} '
        'approvalCode=${result.approvalCode} error=${result.errorMessage}');

    // PRODUCT RULE — do not "fix" this away, other agents. Once the terminal
    // has approved the payment, the customer HAS paid; from their side the
    // payment is done. If Waha's backend then fails to record it
    // (confirmTerminalSession below, the "approved but not recorded" state),
    // that is OUR internal reconciliation problem, never the customer's:
    //  - we can NOT charge the customer a second time for a failure of ours;
    //  - we keep selling as long as the kiosk can create orders and the POS
    //    can process transactions — a backend hiccup does not pause sales.
    // Until changed by an explicit new request, that is the rule.
    // TODO: when the payment is recorded late (retry or operator
    // reconciliation), push a notification to the kiosk so it reloads the
    // invoice and shows it as paid. Until that exists the order can stay
    // unpaid on screen although the card was debited, and the screen may
    // invite the customer to pay again — the rule above is not yet fully met.
    // TODO: keep a durable local record of every approved-but-unrecorded
    // payment (session id, approvalCode, rrn, amount) so it can be retried or
    // reconciled; today it exists only in the trace log
    // ("PAYMENT LATE APPROVAL" / "approved but confirm-to-backend failed").
    //
    // `result` comes from the native side (MainActivity.startPayment), which
    // answers exactly once, on the first SDK callback that carries a
    // definite outcome — never on an ack or step code.
    //
    // "approved" alone is the terminal's verdict (Geidea SDK's own
    // TransactionStatusCode, the same field its sample app trusts) — the
    // approval code is not required. Requiring it here used to cancel the
    // backend session on a real approval that happened to arrive without one,
    // which breaks the rule above: an approved payment is never un-approved
    // by us. Fall back to the RRN, or a fixed placeholder, only to satisfy the
    // backend's non-empty authCode field — never to decide approved/declined.
    if (result.approved) {
      try {
        final rawCode = result.approvalCode?.trim();
        final approvalCode = (rawCode == null || rawCode.isEmpty || rawCode == '?') ? null : rawCode;
        final rrn = result.details['rrn'] as String?;
        final authCode = approvalCode ?? (rrn != null && rrn.isNotEmpty ? rrn : null) ?? 'APPROVED-NO-CODE';
        await widget.apiClient.confirmTerminalSession(
          session.id,
          authCode: authCode,
          notes: {...result.details, 'vendor': 'geidea'},
        );
        final order = await widget.apiClient.getOrder(widget.orderId);
        TraceLog.log('Terminal: session ${session.id} confirmed to backend, order paid');
        if (mounted) Navigator.pop(context, order);
      } catch (e) {
        // Card was charged but the backend couldn't be told — do NOT show
        // this as a plain decline, the customer's card was already debited.
        TraceLog.log('Terminal: approved but confirm-to-backend failed: $e');
        if (mounted) {
          setState(() {
            _failed = true;
            _statusLabel = l10n.terminalApprovedNotRecorded(e.toString());
          });
        }
      }
    } else {
      TraceLog.log('Terminal: declined/failed — ${result.errorMessage ?? "no message"}');
      try { await widget.apiClient.cancelTerminalSession(session.id); } catch (_) {}
      if (mounted) {
        setState(() {
          _failed = true;
          _statusLabel = result.errorMessage ?? l10n.paymentDeclined;
        });
        _scheduleAutoClose();
      }
    }
  }

  // Best-effort: the native SDK call already in flight can't actually be
  // aborted mid-transaction (it's a single platform-channel Future, not a
  // cancellable operation) — this closes the dialog and cancels the
  // backend session, but a transaction the terminal already approved will
  // still go through underneath.
  Future<void> _cancel() async {
    TraceLog.log('Terminal: payment cancelled by user');
    final id = _session?.id;
    if (id != null) {
      try { await widget.apiClient.cancelTerminalSession(id); } catch (_) {}
    }
    unawaited(GeideaTerminalBridge.instance.cancelPayment());
    if (mounted) Navigator.pop(context, null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final done = _failed;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          done
              ? Icon(Icons.error_outline, size: 72, color: scheme.error)
              : _TerminalIcon(color: scheme.primary),
          const SizedBox(height: 24),
          Text(
            done ? l10n.terminalPaymentFailedTitle : l10n.terminalTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Text(
            _statusLabel ?? '',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.outline),
          ),
          if (!done) ...[
            const SizedBox(height: 24),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 32),
          if (done)
            FilledButton(
                onPressed: () => Navigator.pop(context, null),
                child: Text(l10n.terminalClose))
          else
            OutlinedButton.icon(
              icon: const Icon(Icons.cancel_outlined),
              label: Text(l10n.commonCancel),
              onPressed: _cancel,
              style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
            ),
        ],
      ),
    );
  }
}

// Flutter's built-in Material icon set has no dedicated "handheld
// card-reader device" glyph — the bare Icons.contactless wave alone reads
// as a generic NFC symbol, not a terminal, and Icons.point_of_sale reads
// as a cash register. This composes an actual small reader-device shape
// instead: a rounded body, a screen showing the tap-to-pay wave, and a
// keypad hint below it — no external asset needed.
class _TerminalIcon extends StatelessWidget {
  final Color color;
  const _TerminalIcon({required this.color});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 68,
      height: 88,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color, width: 2.5),
        ),
        child: Column(
          children: [
            // Screen — this is what makes it read as a device, not just a
            // floating NFC symbol.
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.contactless, color: scheme.surface, size: 26),
              ),
            ),
            const SizedBox(height: 8),
            // Keypad hint
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                3,
                (i) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Container(
                    width: 8,
                    height: 4,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

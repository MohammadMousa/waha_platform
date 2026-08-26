import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/payment_method.dart';
import '../router/app_router.dart';
import '../services/api_client.dart';
import '../state/auth_service.dart';
import '../state/browsing_mode_service.dart';
import '../state/locale_service.dart';
import '../state/order_flow_controller.dart';
import '../state/store_config_service.dart';
import '../utils/locale_name.dart';

/// Pay screen.
///
/// Flow:
/// 1. Screen opens → shows loading while it:
///    a. Refreshes order status (in case it was already paid externally)
///    b. Loads available payment methods
/// 2. If order is already PAID → shows "Already Paid" status, no buttons.
/// 3. If no methods available → empty state with icon.
/// 4. Otherwise → shows method buttons.
///    - SIMULATED provider → POST /api/orders/{id}/pay
///    - REDIRECT provider → POST /api/orders/{id}/payment-session → open URL → poll
/// 5. Once paid → shows success status; navigates to Success on tap.
class PayScreen extends StatefulWidget {
  const PayScreen({super.key});

  @override
  State<PayScreen> createState() => _PayScreenState();
}

class _PayScreenState extends State<PayScreen> {
  // ---- Pre-load state ----
  bool _ready = false;
  String? _loadError;

  // ---- Invoice / methods ----
  bool _paid = false;
  List<PaymentMethod> _methods = [];

  // ---- Simulated pay ----
  bool _paying = false;
  bool _declined = false;
  String? _declineDetail;

  // ---- Redirect pay ----
  bool _launchingSession = false;
  bool _waitingForConfirmation = false;
  int _pollAttempts = 0;
  Timer? _pollTimer;
  String? _sessionError;
  static const _maxPollAttempts = 150; // ~5 min at 2s

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  /// Load everything before showing content: refresh order status, then
  /// load payment methods. All calls are sequential (queue), not parallel,
  /// so each step has fresh data before the next.
  Future<void> _loadAll() async {
    setState(() {
      _ready = false;
      _loadError = null;
    });

    final flow = context.read<OrderFlowController>();

    // Step 1: Refresh order to get latest status.
    try {
      await flow.refreshOrder();
    } catch (_) {
      // If refresh fails, continue with whatever order data we have.
    }

    // Step 2: If already paid, show paid state and stop.
    if (flow.order?.status == 'PAID') {
      if (mounted) setState(() { _paid = true; _ready = true; });
      return;
    }

    // Step 3: Load payment methods.
    try {
      final mode = browsingModeService.mode.name.toUpperCase();
      final storeId = authService.sessionStoreId ?? storeConfigService.storeId;
      _methods = await context
          .read<ApiClient>()
          .getPaymentMethods(mode: mode, storeId: storeId);
    } catch (_) {
      _loadError = 'Could not load payment methods.';
    }

    if (mounted) setState(() => _ready = true);
  }

  // ---- Simulated payment ----

  Future<void> _paySimulated({required String outcome}) async {
    setState(() {
      _paying = true;
      _declined = false;
    });
    final flow = context.read<OrderFlowController>();
    final result = await flow.pay(simulateOutcome: outcome);
    if (!mounted) return;
    if (result.paid) {
      Navigator.of(context).pushReplacementNamed(Routes.success);
    } else {
      setState(() {
        _paying = false;
        _declined = true;
        _declineDetail = result.detail;
      });
    }
  }

  // ---- Redirect payment ----

  Future<void> _payWithRedirect(String providerKey) async {
    setState(() {
      _launchingSession = true;
      _sessionError = null;
    });
    final flow = context.read<OrderFlowController>();
    try {
      final session = await flow.createPaymentSession(
          provider: providerKey, providerMode: 'REDIRECT');
      final uri = Uri.parse(session.redirectUrl);
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) throw Exception('launch failed');
      if (!mounted) return;
      setState(() {
        _launchingSession = false;
        _waitingForConfirmation = true;
      });
      _pollAttempts = 0;
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollOnce());
    } catch (_) {
      if (mounted) {
        setState(() {
          _launchingSession = false;
          _sessionError = 'Could not start payment — please try again.';
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
        if (mounted) Navigator.of(context).pushReplacementNamed(Routes.success);
        return;
      }
    } catch (_) {}
    if (_pollAttempts >= _maxPollAttempts && mounted) {
      _pollTimer?.cancel();
      setState(() => _waitingForConfirmation = false);
    }
  }

  void _cancelWaiting() {
    _pollTimer?.cancel();
    setState(() => _waitingForConfirmation = false);
  }

  // ---- Route by provider ----

  void _handleMethod(PaymentMethod method) {
    if (method.provider == 'SIMULATED') {
      _paySimulated(outcome: 'SUCCESS');
    } else {
      _payWithRedirect(method.key);
    }
  }

  IconData _iconForMethod(PaymentMethod method) {
    switch (method.key) {
      case 'simulated': return Icons.phone_android_outlined;
      case 'stripe': return Icons.credit_card;
      case 'myfatoorah': return Icons.account_balance_outlined;
      default:
        return method.provider == 'REDIRECT'
            ? Icons.credit_card
            : Icons.payment_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final flow = context.watch<OrderFlowController>();
    final order = flow.order;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.payButton)),
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(l10n, scheme, order),
    );
  }

  Widget _buildContent(AppLocalizations l10n, ColorScheme scheme, order) {
    // Already paid
    if (_paid) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.green, size: 72),
            const SizedBox(height: 16),
            Text(l10n.payAlreadyPaid,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pushReplacementNamed(Routes.success),
              child: Text(l10n.successPaid),
            ),
          ],
        ),
      );
    }

    // Launching / waiting states
    if (_paying || _launchingSession) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_waitingForConfirmation) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              const Text('Waiting for payment confirmation…',
                  textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text('Complete payment in the tab that just opened.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.outline)),
              const SizedBox(height: 24),
              OutlinedButton(
                  onPressed: _pollOnce, child: const Text("I've paid — Check Now")),
              const SizedBox(height: 8),
              TextButton(onPressed: _cancelWaiting, child: const Text('Cancel')),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Order total
          if (order != null) ...[
            Center(
              child: Text(
                '${order.total.toStringAsFixed(2)} ${order.currency ?? ''}',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Decline error
          if (_declined) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Icon(Icons.cancel_outlined, color: scheme.onErrorContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_declineDetail ?? l10n.paymentDeclined,
                        style: TextStyle(color: scheme.onErrorContainer)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Session error
          if (_sessionError != null) ...[
            Text(_sessionError!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
          ],

          // Load error
          if (_loadError != null) ...[
            Text(_loadError!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _loadAll, child: const Text('Retry')),
            const SizedBox(height: 16),
          ],

          // No methods empty state
          if (_methods.isEmpty && _loadError == null) ...[
            const SizedBox(height: 32),
            Icon(Icons.payment_outlined,
                size: 64, color: scheme.outline.withOpacity(0.5)),
            const SizedBox(height: 16),
            Text(l10n.payNoMethods,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: scheme.outline)),
            const SizedBox(height: 8),
            Text(l10n.payNoMethodsSubtitle,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.outline)),
          ],

          // Payment method buttons
          for (final method in _methods) ...[
            _PayMethodButton(
              method: method,
              icon: _iconForMethod(method),
              label: localeName(method.displayName, localeService.locale.languageCode)
                  .let((s) => s.isEmpty ? method.key : s),
              declined: _declined && method.provider == 'SIMULATED',
              retryLabel: l10n.payRetry,
              onTap: _paying ? null : () => _handleMethod(method),
            ),
            const SizedBox(height: 10),
          ],

          // Dev: simulate decline (only when SIMULATED method present)
          if (_methods.any((m) => m.provider == 'SIMULATED') && !_declined) ...[
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => _paySimulated(outcome: 'FAIL'),
              child: const Text('Simulate Decline (dev)',
                  style: TextStyle(fontSize: 12)),
            ),
          ],
        ],
      ),
    );
  }
}

class _PayMethodButton extends StatelessWidget {
  final PaymentMethod method;
  final IconData icon;
  final String label;
  final bool declined;
  final String retryLabel;
  final VoidCallback? onTap;

  const _PayMethodButton({
    required this.method,
    required this.icon,
    required this.label,
    required this.declined,
    required this.retryLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: scheme.onPrimary, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  declined ? retryLabel : label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
              Icon(Icons.arrow_forward_ios,
                  size: 14, color: scheme.onPrimaryContainer.withOpacity(0.5)),
            ],
          ),
        ),
      ),
    );
  }
}

extension _StringX on String {
  String let(String Function(String) fn) => fn(this);
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../router/app_router.dart';
import '../services/api_exceptions.dart';
import '../state/auth_service.dart';
import '../state/browsing_mode_service.dart';
import '../state/order_flow_controller.dart';

/// Invisible transition screen: authenticates, creates the order, then
/// immediately replaces itself with /invoice/{orderId}. The user never
/// "sees" a checkout page — it's just a spinner while the order is minted.
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startCheckout());
  }

  void _startCheckout() {
    final mode = browsingModeService.mode;
    if (mode == BrowsingMode.normal && !authService.isLoggedIn) {
      Navigator.of(context).pushReplacementNamed(
        Routes.login,
        arguments: Routes.checkout,
      );
      return;
    }
    _createOrder();
  }

  Future<void> _createOrder() async {
    setState(() => _error = null);
    final flow = context.read<OrderFlowController>();
    try {
      final order = await flow.checkout();
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(
        Routes.invoice,
        arguments: order.orderId,
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Something went wrong. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 56),
                const SizedBox(height: 16),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _createOrder,
                  child: Text(l10n.browseRetry),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(context)
                      .pushNamedAndRemoveUntil(Routes.cart, (r) => r.isFirst),
                  child: Text(l10n.navCart),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              l10n.checkoutCreating,
              style: TextStyle(color: scheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}

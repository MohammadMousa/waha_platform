import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../l10n/generated/app_localizations.dart';
import '../router/app_router.dart';
import '../state/locale_service.dart';
import '../state/order_flow_controller.dart';
import '../utils/locale_name.dart';

class SuccessScreen extends StatelessWidget {
  const SuccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final flow = context.watch<OrderFlowController>();
    final order = flow.order;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.receiptTitle), automaticallyImplyLeading: false),
      body: order == null
          ? const Center(child: Text('No order to show'))
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 64),
                  const SizedBox(height: 16),
                  Text(l10n.successPaid, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 24),
                  Expanded(
                    child: ListView(
                      children: [
                        ...order.items.map(
                          (line) => ListTile(
                            title: Text(localeName(
                                line.name, localeService.locale.languageCode)),
                            subtitle: Text('x${line.quantity}'),
                            trailing: Text(line.lineTotal.toStringAsFixed(2)),
                          ),
                        ),
                        const Divider(),
                        ListTile(
                          title: Text(l10n.cartSubtotal),
                          trailing: Text(order.subtotal.toStringAsFixed(2)),
                        ),
                        ListTile(
                          title: Text(l10n.cartTax),
                          trailing: Text(order.tax.toStringAsFixed(2)),
                        ),
                        ListTile(
                          title: Text(l10n.cartTotal),
                          trailing: Text(
                            '${order.total.toStringAsFixed(2)} ${order.currency ?? ''}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        // Real now — GET /api/invoices/{orderId} exists and
                        // every order response carries its own invoiceUrl
                        // pre-built. Encode that directly, per the backend
                        // doc, rather than constructing the URL ourselves.
                        if (order.invoiceUrl != null) ...[
                          const Divider(),
                          const SizedBox(height: 12),
                          Text(
                            l10n.successInvoiceQrLabel,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 12),
                          Center(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: Theme.of(context).colorScheme.outlineVariant),
                              ),
                              child: QrImageView(
                                data: order.invoiceUrl!,
                                size: 180,
                                backgroundColor: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Center(
                            child: SelectableText(
                              order.invoiceUrl!,
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: Theme.of(context).colorScheme.outline),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  FilledButton(
                    onPressed: () {
                      context.read<OrderFlowController>().reset();
                      Navigator.of(context)
                          .pushNamedAndRemoveUntil(Routes.landing, (r) => false);
                    },
                    child: Text(l10n.successNewOrder),
                  ),
                ],
              ),
            ),
    );
  }
}

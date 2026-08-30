import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/api_client.dart';
import '../state/auth_service.dart';
import '../state/locale_service.dart';
import '../state/store_config_service.dart';
import '../utils/locale_name.dart';

class PaymentMethodsScreen extends StatefulWidget {
  const PaymentMethodsScreen({super.key});

  @override
  State<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends State<PaymentMethodsScreen> {
  bool _loading = false;
  String? _error;
  List<AdminPaymentMethodView> _methods = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final storeId = authService.sessionStoreId ?? storeConfigService.storeId;
      final methods = await context
          .read<ApiClient>()
          .getAdminPaymentMethods(storeId: storeId, token: authService.token);
      if (mounted) setState(() { _methods = methods; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _toggle(AdminPaymentMethodView method) async {
    final newActive = !method.effectiveActive;
    final api = context.read<ApiClient>();
    final storeId = authService.sessionStoreId ?? storeConfigService.storeId;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Saving…'),
              ]),
            ),
          ),
        ),
      ),
    );

    try {
      await api.setPaymentMethodStoreActive(
          method.id, active: newActive, storeId: storeId, token: authService.token);
      if (!mounted) return;
      Navigator.of(context).pop();
      await _load();
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final lang = localeService.locale.languageCode;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.adminPaymentMethods),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 12),
                      OutlinedButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                )
              : _methods.isEmpty
                  ? Center(
                      child: Text(l10n.payNoMethods,
                          style: TextStyle(color: scheme.outline)),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _methods.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, indent: 16),
                      itemBuilder: (_, i) {
                        final m = _methods[i];
                        final name = _nameOrKey(m.displayName, m.key, lang);
                        return CheckboxListTile(
                          title: Text(name,
                              style: const TextStyle(fontWeight: FontWeight.w500)),
                          subtitle: Text(m.provider,
                              style: TextStyle(fontSize: 12, color: scheme.outline)),
                          value: m.effectiveActive,
                          onChanged: (_) => _toggle(m),
                        );
                      },
                    ),
    );
  }
}

String _nameOrKey(Map<String, dynamic>? displayName, String fallback, String lang) {
  final name = localeName(displayName, lang);
  return name.isEmpty ? fallback : name;
}

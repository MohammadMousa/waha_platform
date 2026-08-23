import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../state/auth_service.dart';
import '../state/store_config_service.dart';
import '../widgets/waha_app_bar.dart';

class OdooAdminScreen extends StatefulWidget {
  const OdooAdminScreen({super.key});

  @override
  State<OdooAdminScreen> createState() => _OdooAdminScreenState();
}

class _OdooAdminScreenState extends State<OdooAdminScreen> {
  final _formKey        = GlobalKey<FormState>();
  final _urlCtrl        = TextEditingController();
  final _keyCtrl        = TextEditingController();
  final _userCtrl       = TextEditingController();
  final _overrideCtrl   = TextEditingController();

  bool _loading       = false;
  bool _configured    = false;
  String? _baseUrl;
  String? _username;
  String? _customerOverride;
  String? _lastCatSync;
  String? _lastProdSync;
  Map<String, dynamic>? _queue;
  String? _error;
  String? _successMsg;

  // Track which store was last loaded to detect changes.
  int? _loadedStoreId;

  void _onStoreChanged() {
    if (!mounted) return;
    final currentStoreId = storeConfigService.storeId;
    if (_loadedStoreId != null && _loadedStoreId != currentStoreId) {
      setState(() {
        _configured       = false;
        _baseUrl          = null;
        _username         = null;
        _customerOverride = null;
        _lastCatSync      = null;
        _lastProdSync     = null;
        _queue            = null;
        _error            = null;
        _successMsg       = null;
        _urlCtrl.clear();
        _userCtrl.clear();
        _overrideCtrl.clear();
      });
      _loadStatus();
    }
  }

  @override
  void initState() {
    super.initState();
    storeConfigService.addListener(_onStoreChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await _loadStatus();
      } catch (e) {
        if (mounted) setState(() => _error = e.toString());
      }
    });
  }

  @override
  void dispose() {
    storeConfigService.removeListener(_onStoreChanged);
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    _userCtrl.dispose();
    _overrideCtrl.dispose();
    super.dispose();
  }

  String? get _token => authService.token;
  int? get _storeId => storeConfigService.storeId;

  // Returns normally on success. Rethrows on error so callers can handle it.
  Future<void> _loadStatus() async {
    final token = _token;
    if (token == null) return;
    final storeId = _storeId;
    setState(() => _loading = true);
    try {
      final status = await context.read<ApiClient>().odooStatus(token, storeId: storeId);
      setState(() {
        _configured       = status['configured'] as bool? ?? false;
        _baseUrl          = status['baseUrl']           as String?;
        _username         = status['username']          as String?;
        _customerOverride = status['customerOverride']  as String?;
        _lastCatSync      = status['lastCategorySyncAt'] as String?;
        _lastProdSync     = status['lastProductSyncAt']  as String?;
        _queue            = status['queue']  as Map<String, dynamic>?;
        if (_baseUrl          != null && _baseUrl!.isNotEmpty)          _urlCtrl.text      = _baseUrl!;
        if (_username         != null && _username!.isNotEmpty)         _userCtrl.text     = _username!;
        if (_customerOverride != null && _customerOverride!.isNotEmpty) _overrideCtrl.text = _customerOverride!;
        _loadedStoreId = storeId;
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final token = _token;
    if (token == null) return;
    setState(() { _loading = true; _error = null; _successMsg = null; });
    try {
      await context.read<ApiClient>().oodooConfigure(
        token,
        _urlCtrl.text.trim(),
        _keyCtrl.text.trim(),
        _userCtrl.text.trim(),
        customerOverride: _overrideCtrl.text.trim(),
        storeId: _storeId,
      );
      _keyCtrl.clear();
      _userCtrl.clear();
      await _loadStatus();
      setState(() => _successMsg = 'Connection saved.');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _pullCategories() async {
    final token = _token;
    if (token == null) return;
    setState(() { _loading = true; _error = null; _successMsg = null; });
    try {
      final count = await context.read<ApiClient>().oodooPullCategories(token, storeId: _storeId);
      await _loadStatus();
      setState(() => _successMsg = count > 0 ? 'Pulled $count categories from Odoo.' : 'Categories already up to date.');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _pushOrders() async {
    final token = _token;
    if (token == null) return;
    setState(() { _loading = true; _error = null; _successMsg = null; });
    try {
      final count = await context.read<ApiClient>().oodooPushOrders(token, storeId: _storeId);
      await _loadStatus();
      setState(() => _successMsg = count > 0 ? 'Pushed $count order(s) to Odoo.' : 'No pending orders to push.');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _pullProducts() async {
    final token = _token;
    if (token == null) return;
    setState(() { _loading = true; _error = null; _successMsg = null; });
    try {
      final (pulled, visible) = await context.read<ApiClient>().oodooPullProducts(token, storeId: _storeId);
      await _loadStatus();
      if (pulled > 0) {
        setState(() => _successMsg = 'Pulled $pulled products from Odoo.');
      } else if (visible > 0) {
        setState(() => _successMsg = 'Already up to date. $visible products available to this store (via inheritance).');
      } else {
        setState(() => _successMsg = 'Already up to date. No products in scope.');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: const WahaAppBar(title: 'Odoo Integration'),
      body: _loading && !_configured
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadStatus,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ── Status banner ──────────────────────────────────────────
                  _StatusCard(configured: _configured, baseUrl: _baseUrl),
                  const SizedBox(height: 20),

                  // ── Error / success ────────────────────────────────────────
                  if (_error != null)
                    _Banner(message: _error!, color: scheme.errorContainer,
                            textColor: scheme.onErrorContainer),
                  if (_successMsg != null)
                    _Banner(message: _successMsg!, color: Colors.green.shade50,
                            textColor: Colors.green.shade900),
                  if (_error != null || _successMsg != null) const SizedBox(height: 12),

                  // ── Configure connection ────────────────────────────────────
                  Text('Connection', style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _urlCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Odoo Base URL',
                            hintText: 'https://mycompany.odoo.com',
                            prefixIcon: Icon(Icons.link),
                          ),
                          keyboardType: TextInputType.url,
                          validator: (v) =>
                              (v == null || v.trim().isEmpty) ? 'Required' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _userCtrl,
                          decoration: InputDecoration(
                            labelText: _configured ? 'Odoo Username (leave blank to keep current)' : 'Odoo Username',
                            hintText: 'admin@mycompany.com',
                            prefixIcon: const Icon(Icons.person_outline),
                          ),
                          keyboardType: TextInputType.emailAddress,
                          validator: (v) {
                            if (!_configured && (v == null || v.trim().isEmpty)) return 'Required';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _keyCtrl,
                          decoration: InputDecoration(
                            labelText: _configured ? 'API Key (leave blank to keep current)' : 'API Key',
                            prefixIcon: const Icon(Icons.key),
                          ),
                          obscureText: true,
                          validator: (v) {
                            if (!_configured && (v == null || v.trim().isEmpty)) return 'Required';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _overrideCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Customer Name (Override, optional)',
                            hintText: 'e.g. oasis.kiosks',
                            prefixIcon: Icon(Icons.person_pin_outlined),
                            helperText: 'All orders use this Odoo customer instead of device/user identity.',
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            icon: _loading
                                ? const SizedBox(width: 16, height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.save_outlined),
                            label: const Text('Save Connection'),
                            onPressed: _loading ? null : _save,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),

                  // ── Catalog pull ───────────────────────────────────────────
                  Text('Catalog Sync', style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Pulls data from Odoo into Waha. Incremental after first run.',
                      style: TextStyle(color: scheme.outline, fontSize: 13)),
                  const SizedBox(height: 12),

                  _SyncRow(
                    label: 'Categories',
                    icon: Icons.category_outlined,
                    lastSync: _lastCatSync,
                    enabled: _configured && !_loading,
                    onPull: _pullCategories,
                  ),
                  const SizedBox(height: 10),
                  _SyncRow(
                    label: 'Products',
                    icon: Icons.inventory_2_outlined,
                    lastSync: _lastProdSync,
                    enabled: _configured && !_loading,
                    onPull: _pullProducts,
                  ),

                  if (_queue != null) ...[
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Text('Order Sync Queue',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                        ),
                        FilledButton.icon(
                          icon: _loading
                              ? const SizedBox(width: 14, height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.upload_outlined, size: 18),
                          label: const Text('Push Now'),
                          onPressed: _configured && !_loading && (_queue?['pending'] ?? 0) > 0 ? _pushOrders : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _QueueStats(queue: _queue!),
                  ],

                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final bool configured;
  final String? baseUrl;
  const _StatusCard({required this.configured, this.baseUrl});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: configured ? Colors.green.shade50 : scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              configured ? Icons.check_circle_outline : Icons.radio_button_unchecked,
              color: configured ? Colors.green.shade700 : scheme.outline,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    configured ? 'Connected' : 'Not configured',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: configured ? Colors.green.shade800 : scheme.onSurface,
                    ),
                  ),
                  if (baseUrl != null && baseUrl!.isNotEmpty)
                    Text(baseUrl!, style: TextStyle(fontSize: 12, color: scheme.outline)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final String message;
  final Color color;
  final Color textColor;
  const _Banner({required this.message, required this.color, required this.textColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
      child: Text(message, style: TextStyle(color: textColor, fontSize: 13)),
    );
  }
}

class _SyncRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final String? lastSync;
  final bool enabled;
  final VoidCallback onPull;
  const _SyncRow({required this.label, required this.icon, this.lastSync,
                   required this.enabled, required this.onPull});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 22, color: scheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    lastSync != null ? 'Last sync: ${_fmtTs(lastSync!)}' : 'Never synced',
                    style: TextStyle(fontSize: 12, color: scheme.outline),
                  ),
                ],
              ),
            ),
            FilledButton.tonal(
              onPressed: enabled ? onPull : null,
              child: const Text('Pull'),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtTs(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.year}-${_p(dt.month)}-${_p(dt.day)} ${_p(dt.hour)}:${_p(dt.minute)}';
    } catch (_) {
      return iso;
    }
  }

  String _p(int n) => n.toString().padLeft(2, '0');
}

class _QueueStats extends StatelessWidget {
  final Map<String, dynamic> queue;
  const _QueueStats({required this.queue});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Chip(label: 'Pending', value: '${queue['pending'] ?? 0}', color: Colors.orange),
        const SizedBox(width: 8),
        _Chip(label: 'Failed',  value: '${queue['failed']  ?? 0}', color: Colors.red),
        const SizedBox(width: 8),
        _Chip(label: 'Done',    value: '${queue['done']    ?? 0}', color: Colors.green),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Chip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: color)),
            Text(label, style: TextStyle(fontSize: 11, color: color)),
          ],
        ),
      ),
    );
  }
}

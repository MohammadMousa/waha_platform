import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../services/local_prefs.dart';
import '../l10n/generated/app_localizations.dart';
import '../router/app_router.dart';
import '../services/api_client.dart';
import '../state/auth_service.dart';
import '../state/browsing_mode_service.dart';
import '../state/locale_service.dart';
import '../state/order_flow_controller.dart';
import '../state/permission_service.dart';
import '../state/simulator_service.dart';
import '../state/store_config_service.dart';
import '../utils/locale_name.dart';
import 'simulator_settings_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Kiosk timer fields
  late final TextEditingController _beforeWarn;
  late final TextEditingController _beforeCountdown;
  late final TextEditingController _afterWarn;
  late final TextEditingController _afterCountdown;
  String? _timerError;

  // Dev tools unlock: tap the version line 10 times
  int _tapCount = 0;
  bool _devUnlocked = false;

  // Dev tools — store ID override
  late final TextEditingController _storeId;
  String? _storeIdError;

  // Dev tools — register form
  final _regUsername = TextEditingController();
  final _regPassword = TextEditingController();
  String? _regResult;
  bool _registering = false;

  @override
  void initState() {
    super.initState();
    _beforeWarn = TextEditingController(
      text: '${kioskTimerConfig.beforeInvoiceIdleWarningAfter.inSeconds}',
    );
    _beforeCountdown = TextEditingController(
      text: '${kioskTimerConfig.beforeInvoiceWarningCountdown.inSeconds}',
    );
    _afterWarn = TextEditingController(
      text: '${kioskTimerConfig.afterInvoiceIdleWarningAfter.inSeconds}',
    );
    _afterCountdown = TextEditingController(
      text: '${kioskTimerConfig.afterInvoiceWarningCountdown.inSeconds}',
    );
    _storeId = TextEditingController(text: storeConfigService.storeId?.toString() ?? '');
    _devUnlocked = LocalPrefs.devToolsUnlocked;
  }

  @override
  void dispose() {
    _beforeWarn.dispose();
    _beforeCountdown.dispose();
    _afterWarn.dispose();
    _afterCountdown.dispose();
    _storeId.dispose();
    _regUsername.dispose();
    _regPassword.dispose();
    super.dispose();
  }

  void _onVersionTap() {
    _tapCount++;
    if (_tapCount >= 10 && !_devUnlocked) {
      setState(() => _devUnlocked = true);
      LocalPrefs.setDevToolsUnlocked(true);
      if (AppConfig.simulatorAvailable) {
        context.read<SimulatorService>().showDevTools();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Developer tools unlocked')),
      );
    } else if (_tapCount >= 7 && !_devUnlocked) {
      final remaining = 10 - _tapCount;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$remaining more tap${remaining == 1 ? '' : 's'} to unlock dev tools'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  void _hideDevTools() {
    setState(() {
      _devUnlocked = false;
      _tapCount = 0;
    });
    LocalPrefs.setDevToolsUnlocked(false);
  }

  int? _parseSeconds(String s) {
    final v = int.tryParse(s.trim());
    return (v != null && v > 0) ? v : null;
  }

  void _saveTimers() {
    final bw = _parseSeconds(_beforeWarn.text);
    final bc = _parseSeconds(_beforeCountdown.text);
    final aw = _parseSeconds(_afterWarn.text);
    final ac = _parseSeconds(_afterCountdown.text);
    if ([bw, bc, aw, ac].contains(null)) {
      setState(() => _timerError = 'All values must be positive whole numbers.');
      return;
    }
    kioskTimerConfig.update(
      beforeInvoiceIdleWarningAfter: Duration(seconds: bw!),
      beforeInvoiceWarningCountdown: Duration(seconds: bc!),
      afterInvoiceIdleWarningAfter: Duration(seconds: aw!),
      afterInvoiceWarningCountdown: Duration(seconds: ac!),
    );
    setState(() => _timerError = null);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.settingsSaveTimers)),
    );
  }

  Future<void> _saveStoreId() async {
    final parsed = int.tryParse(_storeId.text.trim());
    if (parsed == null || parsed <= 0) {
      setState(() => _storeIdError = 'Store ID must be a positive number.');
      return;
    }
    setState(() => _storeIdError = null);
    final flow = context.read<OrderFlowController>();
    final api  = context.read<ApiClient>();
    final hadItems = flow.cart.isNotEmpty;

    try {
      // If logged in, update the backend session so store-scoped APIs use the
      // new store immediately — not just after the next login.
      if (authService.isLoggedIn) {
        await authService.selectStore(api, parsed);
      } else {
        storeConfigService.setStoreId(parsed);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Store update failed: $e'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    if (hadItems) flow.clearCart();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(hadItems
            ? 'Store updated — cart cleared (items were scoped to old store).'
            : 'Store updated.'),
      ));
    }
  }

  Future<void> _register() async {
    final u = _regUsername.text.trim();
    final p = _regPassword.text.trim();
    if (u.isEmpty || p.isEmpty) {
      setState(() => _regResult = 'Username and password are required.');
      return;
    }
    setState(() {
      _registering = true;
      _regResult = null;
    });
    try {
      await authService.register(context.read<ApiClient>(), u, p);
      if (mounted) setState(() => _regResult = 'Registered and logged in as $u.');
    } catch (e) {
      if (mounted) setState(() => _regResult = 'Failed: $e');
    } finally {
      if (mounted) setState(() => _registering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentMode = context.watch<BrowsingModeService>().mode;
    final currentLocale = context.watch<LocaleService>().locale;
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navSettings)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── Language ──────────────────────────────────────────────────────
          Text(l10n.settingsLanguage, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          SegmentedButton<Locale>(
            segments: const [
              ButtonSegment(value: Locale('en'), label: Text('English')),
              ButtonSegment(value: Locale('ar'), label: Text('العربية')),
            ],
            selected: {currentLocale},
            onSelectionChanged: (sel) => localeService.setLocale(sel.first),
          ),

          const Divider(height: 40),

          // ── App Mode ──────────────────────────────────────────────────────
          Text(l10n.settingsAppMode, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          DropdownButtonFormField<BrowsingMode>(
            initialValue: currentMode,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: BrowsingMode.values
                .where((m) => m.availableOnCurrentPlatform || m == currentMode)
                .map((m) => DropdownMenuItem(value: m, child: Text(_modeLabel(m, l10n))))
                .toList(),
            onChanged: (m) {
              if (m != null) browsingModeService.setMode(m);
            },
          ),
          if (!currentMode.availableOnCurrentPlatform) ...[
            const SizedBox(height: 6),
            Text(
              '${_modeLabel(currentMode, l10n)} is normally used on '
              '${currentMode.platforms.map(_platformLabel).join(' or ')} — '
              'this platform is ${_platformLabel(currentPlatform())}.',
              style: const TextStyle(color: Colors.orange, fontSize: 13),
            ),
          ],

          const Divider(height: 40),

          // ── Kiosk Timers ─────────────────────────────────────────────────
          // Only take effect in Kiosk mode. Two contexts: before-invoice and
          // after-invoice, each with a warn delay and a countdown duration.
          Text(l10n.settingsKioskTimers, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 14),
          _SecondsField(label: 'Before invoice — warn after (s)', controller: _beforeWarn),
          const SizedBox(height: 10),
          _SecondsField(label: 'Before invoice — countdown (s)', controller: _beforeCountdown),
          const SizedBox(height: 10),
          _SecondsField(label: 'After invoice — warn after (s)', controller: _afterWarn),
          const SizedBox(height: 10),
          _SecondsField(label: 'After invoice — countdown (s)', controller: _afterCountdown),
          if (_timerError != null) ...[
            const SizedBox(height: 6),
            Text(_timerError!, style: const TextStyle(color: Colors.red, fontSize: 13)),
          ],
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(onPressed: _saveTimers, child: Text(l10n.settingsSaveTimers)),
          ),

          // ── Admin: Payment Methods + Integrations ─────────────────────────
          if (context.watch<PermissionService>().can('MANAGE_STORES')) ...[
            const Divider(height: 40),
            Text('Admin', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            _AdminPaymentMethodsPanel(),
            const SizedBox(height: 10),
            _ServerConnectionPanel(),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.sync_outlined),
              label: const Text('Odoo Integration'),
              onPressed: () => Navigator.of(context).pushNamed(Routes.odooAdmin),
            ),
          ],

          const SizedBox(height: 48),

          // ── Version / Dev Tools unlock ────────────────────────────────────
          // Tap 10 times to reveal dev tools.
          Center(
            child: GestureDetector(
              onTap: _onVersionTap,
              child: Text(
                'v0.1 (dev)',
                style: TextStyle(
                  color: _devUnlocked ? scheme.primary : scheme.outlineVariant,
                  fontSize: 12,
                ),
              ),
            ),
          ),

          // ── Dev Tools ─────────────────────────────────────────────────────
          if (_devUnlocked) ...[
            const SizedBox(height: 20),
            _DevToolsPanel(
              storeIdController: _storeId,
              storeIdError: _storeIdError,
              onSaveStoreId: _saveStoreId,
              regUsername: _regUsername,
              regPassword: _regPassword,
              regResult: _regResult,
              registering: _registering,
              onRegister: _register,
              onHide: _hideDevTools,
            ),
          ],

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── Dev Tools Panel ───────────────────────────────────────────────────────────
// Shown only after 10 taps on the version label. Collapsed by default so the
// screen doesn't feel cluttered during normal operation.

class _DevToolsPanel extends StatefulWidget {
  final TextEditingController storeIdController;
  final String? storeIdError;
  final VoidCallback onSaveStoreId;
  final TextEditingController regUsername;
  final TextEditingController regPassword;
  final String? regResult;
  final bool registering;
  final VoidCallback onRegister;
  final VoidCallback onHide;

  const _DevToolsPanel({
    required this.storeIdController,
    required this.storeIdError,
    required this.onSaveStoreId,
    required this.regUsername,
    required this.regPassword,
    required this.regResult,
    required this.registering,
    required this.onRegister,
    required this.onHide,
  });

  @override
  State<_DevToolsPanel> createState() => _DevToolsPanelState();
}

class _DevToolsPanelState extends State<_DevToolsPanel> {
  bool _expanded = false;
  bool _obscurePass = true;
  bool _showScanToast = LocalPrefs.showScanSuccessToast;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: scheme.errorContainer.withValues(alpha: 0.15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(Icons.developer_mode_outlined, color: scheme.error, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Developer Tools',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: scheme.error,
                      ),
                    ),
                  ),
                  Tooltip(
                    message: 'Hide Developer Tools',
                    child: IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.visibility_off_outlined, color: scheme.error, size: 20),
                      onPressed: widget.onHide,
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: scheme.error,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            Divider(height: 1, color: scheme.error.withValues(alpha: 0.2)),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Scan feedback
                  const Text('Scan feedback',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    title: const Text('Show footer toast on successful scan'),
                    subtitle: const Text(
                      'Off by default — the scan sound already confirms success. '
                      'Failures always show a blocking dialog regardless of this.',
                    ),
                    value: _showScanToast,
                    onChanged: (value) {
                      final next = value ?? false;
                      setState(() => _showScanToast = next);
                      LocalPrefs.setShowScanSuccessToast(next);
                    },
                  ),

                  const Divider(height: 32),

                  // Store ID override
                  const Text('Store ID override',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: widget.storeIdController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Store ID',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(onPressed: widget.onSaveStoreId, child: const Text('Set')),
                    ],
                  ),
                  if (widget.storeIdError != null) ...[
                    const SizedBox(height: 4),
                    Text(widget.storeIdError!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                  ],
                  OutlinedButton.icon(
                    icon: const Icon(Icons.storefront_outlined),
                    label: Text(
                      storeConfigService.storeId != null
                          ? 'Store #${storeConfigService.storeId} — pick from list'
                          : 'Pick from store list',
                    ),
                    onPressed: () => Navigator.of(context).pushNamed(Routes.storePicker),
                  ),

                  const Divider(height: 32),

                  // Register new account
                  const Text('Register account',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: widget.regUsername,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: widget.regPassword,
                    obscureText: _obscurePass,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePass ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscurePass = !_obscurePass),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: widget.registering ? null : widget.onRegister,
                      child: widget.registering
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Register & Login'),
                    ),
                  ),
                  if (widget.regResult != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      widget.regResult!,
                      style: TextStyle(
                        fontSize: 13,
                        color: widget.regResult!.startsWith('Failed')
                            ? Colors.red
                            : Colors.green.shade700,
                      ),
                    ),
                  ],

                  // Simulator settings (if available)
                  if (AppConfig.simulatorAvailable) ...[
                    const Divider(height: 32),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.settings_remote_outlined),
                      label: const Text('Simulator Settings'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const SimulatorSettingsScreen()),
                      ),
                    ),
                  ],

                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _SecondsField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  const _SecondsField({required this.label, required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}

String _modeLabel(BrowsingMode m, AppLocalizations l10n) => switch (m) {
      BrowsingMode.normal => l10n.modeNormal,
      BrowsingMode.kiosk => l10n.modeKiosk,
      BrowsingMode.shopping => l10n.modeShopping,
    };

String _platformLabel(SupportedPlatform p) => switch (p) {
      SupportedPlatform.web => 'Web',
      SupportedPlatform.android => 'Android',
      SupportedPlatform.desktop => 'Desktop',
    };

// ── Admin: Payment Methods Panel ──────────────────────────────────────────────
// Expandable tile in the Admin section. Loads all payment methods for the
// current store and shows a checklist. Toggling a checkbox calls the backend
// with a blocking loading dialog and shows success/error feedback.

class _AdminPaymentMethodsPanel extends StatefulWidget {
  @override
  State<_AdminPaymentMethodsPanel> createState() => _AdminPaymentMethodsPanelState();
}

class _AdminPaymentMethodsPanelState extends State<_AdminPaymentMethodsPanel> {
  bool _expanded = false;
  bool _loading = false;
  String? _error;
  List<AdminPaymentMethodView> _methods = [];

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final storeId = authService.sessionStoreId ?? storeConfigService.storeId;
      final methods = await context.read<ApiClient>().getAdminPaymentMethods(storeId: storeId, token: authService.token);
      if (mounted) setState(() { _methods = methods; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _toggle(AdminPaymentMethodView method) async {
    final newActive = !method.effectiveActive;
    final api = context.read<ApiClient>();
    final storeId = authService.sessionStoreId ?? storeConfigService.storeId;

    // Show blocking dialog — prevents double-tap and signals feedback
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Saving…'),
            ]),
          ),
        )),
      ),
    );

    try {
      await api.setPaymentMethodStoreActive(method.id, active: newActive, storeId: storeId, token: authService.token);
      if (!mounted) return;
      Navigator.of(context).pop(); // close dialog
      await _load(); // refresh list
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
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final lang = localeService.locale.languageCode;

    return Card(
      elevation: 0,
      color: scheme.surfaceVariant.withOpacity(0.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              final opening = !_expanded;
              setState(() => _expanded = opening);
              if (opening && _methods.isEmpty && !_loading) _load();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(Icons.payment_outlined, size: 20, color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(l10n.adminPaymentMethods,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                      color: scheme.outline),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                    const SizedBox(height: 8),
                    TextButton(onPressed: _load, child: const Text('Retry')),
                  ],
                ),
              )
            else if (_methods.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(l10n.payNoMethods,
                    style: TextStyle(color: scheme.outline)),
              )
            else
              for (final m in _methods)
                CheckboxListTile(
                  title: Text(
                    _nameOrKey(m.displayName, m.key, lang),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(m.provider,
                      style: TextStyle(fontSize: 12, color: scheme.outline)),
                  value: m.effectiveActive,
                  onChanged: (_) => _toggle(m),
                  dense: true,
                ),
          ],
        ],
      ),
    );
  }
}

String _nameOrKey(Map<String, dynamic>? displayName, String fallback, String lang) {
  final name = localeName(displayName, lang);
  return name.isEmpty ? fallback : name;
}

// ── Server Connection panel ───────────────────────────────────────────────────

enum _ServerPreset {
  emulator('Emulator — 10.0.2.2', '10.0.2.2', 8081),
  localhost('Localhost', 'localhost', 8081),
  custom('Custom', '', 8081);

  final String label;
  final String defaultHost;
  final int defaultPort;
  const _ServerPreset(this.label, this.defaultHost, this.defaultPort);
}

class _ServerConnectionPanel extends StatefulWidget {
  @override
  State<_ServerConnectionPanel> createState() => _ServerConnectionPanelState();
}

class _ServerConnectionPanelState extends State<_ServerConnectionPanel> {
  bool _expanded = false;
  bool _useDefault = false;
  _ServerPreset _preset = _ServerPreset.custom;
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  bool _saving = false;
  String? _result;

  @override
  void initState() {
    super.initState();
    final stored = LocalPrefs.apiBaseUrl;
    _useDefault = stored == null || stored.isEmpty;

    // Parse host + port from the stored override, or from the current resolved URL.
    final toParse = (stored != null && stored.isNotEmpty) ? stored : AppConfig.apiBaseUrl;
    final uri = Uri.tryParse(toParse);
    _hostCtrl = TextEditingController(text: uri?.host ?? '');
    _portCtrl = TextEditingController(text: (uri?.hasPort == true ? uri!.port : 8081).toString());
    _detectPreset();
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  void _detectPreset() {
    final host = _hostCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim()) ?? 8081;
    for (final p in _ServerPreset.values) {
      if (p != _ServerPreset.custom && p.defaultHost == host && p.defaultPort == port) {
        _preset = p;
        return;
      }
    }
    _preset = _ServerPreset.custom;
  }

  void _selectPreset(_ServerPreset p) {
    setState(() {
      _preset = p;
      if (p != _ServerPreset.custom) {
        _hostCtrl.text = p.defaultHost;
        _portCtrl.text = p.defaultPort.toString();
      }
    });
  }

  String get _previewUrl {
    final h = _hostCtrl.text.trim();
    final port = _portCtrl.text.trim();
    if (h.isEmpty) return '';
    return 'http://$h:$port';
  }

  Future<void> _save() async {
    setState(() { _saving = true; _result = null; });
    try {
      if (_useDefault) {
        await LocalPrefs.clearApiBaseUrl();
        if (mounted) setState(() { _saving = false; _result = '✓ Override cleared — using app default'; });
        return;
      }
      final url = _previewUrl;
      if (url.isEmpty) { setState(() { _saving = false; }); return; }
      await LocalPrefs.setApiBaseUrl(url);
      final token = authService.token;
      if (token != null) {
        await context.read<ApiClient>().updateConfig({'publicBaseUrl': url}, token: token);
      }
      if (mounted) setState(() { _saving = false; _result = '✓ Saved — restart app to reconnect'; });
    } catch (e) {
      if (mounted) setState(() { _saving = false; _result = 'Local saved. Backend: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fieldsEnabled = !_useDefault;

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(Icons.dns_outlined, color: scheme.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Server Connection',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                      color: scheme.outline),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Use app default checkbox ──────────────────────────
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Use app default'),
                    subtitle: Text(
                      'Falls back to built-in platform URL (LAN / emulator / localhost)',
                      style: TextStyle(fontSize: 11, color: scheme.outline),
                    ),
                    value: _useDefault,
                    onChanged: (v) => setState(() => _useDefault = v!),
                  ),
                  const SizedBox(height: 8),

                  // ── Preset dropdown ───────────────────────────────────
                  _FieldRow(
                    label: 'Preset',
                    enabled: fieldsEnabled,
                    child: DropdownButtonFormField<_ServerPreset>(
                      value: _preset,
                      isDense: true,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        isDense: true,
                        enabled: fieldsEnabled,
                      ),
                      items: _ServerPreset.values
                          .map((p) => DropdownMenuItem(
                                value: p,
                                child: Text(p.label),
                              ))
                          .toList(),
                      onChanged: fieldsEnabled ? (p) => _selectPreset(p!) : null,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // ── Host ─────────────────────────────────────────────
                  _FieldRow(
                    label: 'Host',
                    enabled: fieldsEnabled,
                    child: TextField(
                      controller: _hostCtrl,
                      enabled: fieldsEnabled,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                        hintText: '192.168.1.x',
                      ),
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      onChanged: (_) => setState(_detectPreset),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // ── Port ─────────────────────────────────────────────
                  _FieldRow(
                    label: 'Port',
                    enabled: fieldsEnabled,
                    child: SizedBox(
                      width: 100,
                      child: TextField(
                        controller: _portCtrl,
                        enabled: fieldsEnabled,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                          hintText: '8081',
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(_detectPreset),
                      ),
                    ),
                  ),

                  // ── URL preview ───────────────────────────────────────
                  if (!_useDefault && _previewUrl.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      _previewUrl,
                      style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: scheme.primary),
                    ),
                  ],

                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Save & Apply'),
                    ),
                  ),
                  if (_result != null) ...[
                    const SizedBox(height: 8),
                    Text(_result!,
                        style: TextStyle(fontSize: 12, color: scheme.outline)),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  final String label;
  final Widget child;
  final bool enabled;
  const _FieldRow({required this.label, required this.child, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: enabled ? scheme.onSurface : scheme.outline,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: child),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../l10n/generated/app_localizations.dart';
import '../router/app_router.dart';
import '../services/api_client.dart';
import '../state/auth_service.dart';
import '../state/browsing_mode_service.dart';
import '../state/locale_service.dart';
import '../state/order_flow_controller.dart';
import '../state/store_config_service.dart';
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

  void _saveStoreId() {
    final parsed = int.tryParse(_storeId.text.trim());
    if (parsed == null || parsed <= 0) {
      setState(() => _storeIdError = 'Store ID must be a positive number.');
      return;
    }
    setState(() => _storeIdError = null);
    final flow = context.read<OrderFlowController>();
    final hadItems = flow.cart.isNotEmpty;
    storeConfigService.setStoreId(parsed);
    // Cart items are scoped to the old store's products — clear on store switch
    // to prevent 409s when the new store's scope chain differs.
    if (hadItems) flow.clearCart();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(hadItems
          ? 'Store updated — cart cleared (items were scoped to old store).'
          : 'Store updated.'),
    ));
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

  const _DevToolsPanel({
    required this.storeIdController,
    required this.storeIdError,
    required this.onSaveStoreId,
    required this.regUsername,
    required this.regPassword,
    required this.regResult,
    required this.registering,
    required this.onRegister,
  });

  @override
  State<_DevToolsPanel> createState() => _DevToolsPanelState();
}

class _DevToolsPanelState extends State<_DevToolsPanel> {
  bool _expanded = false;
  bool _obscurePass = true;

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

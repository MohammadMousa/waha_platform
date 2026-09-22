import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../services/geidea_terminal_bridge.dart';
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
import '../services/trace_log.dart';
import '../services/usb_diagnostics.dart';
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

  // Terminal (Geidea) payment timeout
  late final TextEditingController _terminalTimeout;
  String? _terminalTimeoutError;

  // "Detect Payment Terminals" manual test button
  bool _detectingTerminal = false;

  // Dev tools unlock: tap the version line 10 times
  int _tapCount = 0;
  bool _devUnlocked = false;

  // Cart's bottom nav bar visibility in Kiosk mode — hidden by default.
  bool _showCartMenuInKiosk = false;

  // Kiosk idle/inactivity timers — off by default (see LocalPrefs doc comment).
  bool _timersEnabled = false;

  // Dev tools — store ID override
  late final TextEditingController _storeId;
  String? _storeIdError;

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
    _terminalTimeout =
        TextEditingController(text: '${LocalPrefs.terminalTimeoutSeconds}');
    _devUnlocked = LocalPrefs.devToolsUnlocked;
    _showCartMenuInKiosk = LocalPrefs.showCartMenuInKiosk;
    _timersEnabled = LocalPrefs.kioskTimersEnabled;
  }

  @override
  void dispose() {
    _beforeWarn.dispose();
    _beforeCountdown.dispose();
    _afterWarn.dispose();
    _afterCountdown.dispose();
    _storeId.dispose();
    _terminalTimeout.dispose();
    super.dispose();
  }

  void _onVersionTap() {
    _tapCount++;
    if (_tapCount >= 10 && !_devUnlocked) {
      setState(() => _devUnlocked = true);
      LocalPrefs.setDevToolsUnlocked(true);
      // Harmless no-op when the overlay is compiled/toggled off — see
      // SimulatorOverlay's own gate.
      context.read<SimulatorService>().showDevTools();
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

  // Clamped to [10, 80]s — the backend's own PENDING→TIMEOUT window for a
  // terminal session is a fixed 90s (TerminalSessionService.java); keeping
  // this comfortably under that means the Kiosk always gives up and cancels
  // its own session before the backend's window can lapse mid-transaction,
  // so a value here can never trigger that race.
  static const _minTerminalTimeout = 10;
  static const _maxTerminalTimeout = 80;

  void _saveTerminalTimeout() {
    final v = _parseSeconds(_terminalTimeout.text);
    if (v == null || v < _minTerminalTimeout || v > _maxTerminalTimeout) {
      setState(() => _terminalTimeoutError =
          'Must be between $_minTerminalTimeout and $_maxTerminalTimeout seconds.');
      return;
    }
    LocalPrefs.setTerminalTimeoutSeconds(v);
    setState(() => _terminalTimeoutError = null);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Terminal payment timeout saved.')),
    );
  }

  Future<void> _detectTerminal() async {
    setState(() => _detectingTerminal = true);
    final found = await GeideaTerminalBridge.instance.detectTerminal();
    if (!mounted) return;
    setState(() => _detectingTerminal = false);
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        icon: Icon(
          found ? Icons.check_circle_outline : Icons.error_outline,
          color: found ? Colors.green : Colors.red,
          size: 40,
        ),
        title: Text(found ? 'Terminal Found' : 'No Terminal Found'),
        content: Text(found
            ? 'A payment terminal is connected and responding.'
            : 'No payment terminal was detected. Check the USB cable and '
                'make sure the terminal is powered on.'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
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
          const SizedBox(height: 10),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Row(
              children: [
                const Text('Enable Idle Timers'),
                IconButton(
                  icon: const Icon(Icons.info_outline, size: 20),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      content: const Text(
                        'Only affects inactivity redirects (before- and after-invoice, '
                        'both below). On by default — trusted on real hardware. Turn '
                        'off if you need the app to never redirect home for mere '
                        'inactivity, on any screen. A paid order still shows a brief '
                        'success popup and redirects home on its own regardless of '
                        'this. Does NOT affect the separate "Wait for terminal" '
                        'timeout further down — that one stays on always, as a safety '
                        'cutoff so a stuck terminal call can\'t hang the app forever.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            value: _timersEnabled,
            onChanged: (value) {
              setState(() => _timersEnabled = value);
              LocalPrefs.setKioskTimersEnabled(value);
            },
          ),
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
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.settingsShowCartMenuKiosk),
            value: _showCartMenuInKiosk,
            onChanged: (value) {
              setState(() => _showCartMenuInKiosk = value);
              LocalPrefs.setShowCartMenuInKiosk(value);
            },
          ),

          const Divider(height: 40),

          // ── Terminal Payment (Geidea) ───────────────────────────────────
          // How long the Kiosk waits on a card-present terminal transaction
          // before giving up — see _saveTerminalTimeout for why it's capped.
          Text('Terminal Payment', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 14),
          _SecondsField(
            label: 'Wait for terminal — timeout (s)',
            controller: _terminalTimeout,
          ),
          if (_terminalTimeoutError != null) ...[
            const SizedBox(height: 6),
            Text(_terminalTimeoutError!, style: const TextStyle(color: Colors.red, fontSize: 13)),
          ],
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _saveTerminalTimeout,
              child: const Text('Save'),
            ),
          ),
          const SizedBox(height: 12),
          // Manual test hook: forces a fresh connection attempt right now
          // (instead of waiting for the app's own slow background retry)
          // and reports whether the terminal answered — useful for
          // verifying cabling/power on real hardware without having to
          // start a whole checkout flow.
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              icon: _detectingTerminal
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.contactless_outlined),
              label: Text(_detectingTerminal ? 'Scanning…' : 'Detect Payment Terminals'),
              onPressed: _detectingTerminal ? null : _detectTerminal,
            ),
          ),

          // ── Admin: Payment Methods + Integrations ─────────────────────────
          if (context.watch<PermissionService>().can('MANAGE_STORES')) ...[
            const Divider(height: 40),
            Text('Admin', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            _AdminPaymentMethodsPanel(),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.sync_outlined),
              label: const Text('Odoo Integration'),
              onPressed: () => Navigator.of(context).pushNamed(Routes.odooAdmin),
            ),
          ],
          if (context.watch<PermissionService>().can('MANAGE_STORES')) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.receipt_outlined),
              label: const Text('Edit Receipt Info'),
              onPressed: () => Navigator.of(context).pushNamed(Routes.receiptInfoEdit),
            ),
          ],
          if (context.watch<PermissionService>().can('EDIT_RESOURCES')) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('Resource Explorer'),
              onPressed: () => Navigator.of(context).pushNamed(Routes.resourceExplorer),
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
          // No permission check here on purpose — Server Connection has to be
          // reachable even when the device can't log in yet (e.g. right after
          // the LAN IP changes and the configured server is now unreachable).
          if (_devUnlocked) ...[
            const SizedBox(height: 20),
            _ServerConnectionPanel(),
            const SizedBox(height: 20),
            _DevToolsPanel(
              storeIdController: _storeId,
              storeIdError: _storeIdError,
              onSaveStoreId: _saveStoreId,
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
  final VoidCallback onHide;

  const _DevToolsPanel({
    required this.storeIdController,
    required this.storeIdError,
    required this.onSaveStoreId,
    required this.onHide,
  });

  @override
  State<_DevToolsPanel> createState() => _DevToolsPanelState();
}

class _DevToolsPanelState extends State<_DevToolsPanel> {
  bool _expanded = false;
  bool _showScanToast = LocalPrefs.showScanSuccessToast;
  bool _simForceEnabled = LocalPrefs.simulatorForceEnabled;
  // In-memory only (see GeideaTerminalBridge.fakeTerminalEnabled) — always
  // starts false on a fresh app launch, regardless of what it was set to
  // last session.
  bool _fakeTerminalEnabled = GeideaTerminalBridge.fakeTerminalEnabled;

  // Diagnostic trace logging — off by default (see LocalPrefs.loggingEnabled).
  // Persisted, unlike _fakeTerminalEnabled above — survives restart.
  bool _loggingEnabled = LocalPrefs.loggingEnabled;

  // Opens a dialog with the current USB snapshot (see UsbDiagnostics). The
  // Copy button confirms in place ("Copied"), since a snackbar would sit
  // behind the dialog's barrier.
  Future<void> _showUsbDevices() async {
    final text = await UsbDiagnostics.inventory(reason: 'settings');
    if (!mounted) return;
    await _showTextDialog('USB devices', text);
  }

  // Runs [run] behind a progress dialog, then shows its text. For the
  // terminal tools below, some of which take several seconds.
  Future<void> _showDiagnostic(String title, Future<String> Function() run) async {
    final nav = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: const Row(
          children: [
            SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)),
            SizedBox(width: 16),
            Expanded(child: Text('Running…')),
          ],
        ),
      ),
    );
    String text;
    try {
      text = await run();
    } catch (e) {
      text = 'Failed: $e';
    }
    if (!mounted) return;
    nav.pop();
    await _showTextDialog(title, text);
  }

  Future<String> _uploadLogText() async {
    final r = await GeideaTerminalBridge.instance.uploadLog();
    if (r['ok'] == true) {
      return 'Uploaded.\n\n'
          'LOG ID: ${r['id']}\n'
          '${r['url']}\n\n'
          '${r['fileName']} (${r['bytes']} bytes)\n\n'
          'Send the LOG ID to the developer.';
    }
    return 'Upload FAILED.\n\n${r['message'] ?? 'unknown error'}\n\nServer: ${r['baseUrl'] ?? 'unknown'}';
  }

  Future<void> _confirmClearLog() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear log?'),
        content: const Text('Deletes the trace log file on this device. It cannot be undone — upload it first if you still need it.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Clear')),
        ],
      ),
    );
    if (ok != true) return;
    final cleared = await GeideaTerminalBridge.instance.clearLog();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(cleared ? 'Log cleared' : 'No log file to clear')),
    );
  }

  Future<String> _handshakeText() async {
    final r = await GeideaTerminalBridge.instance.checkStatus();
    final status = '${r['status']}';
    final verdict = switch (status) {
      'ok' => 'The terminal ANSWERED over USB.',
      'error' => 'The terminal or SDK answered with an error.',
      'timeout' => 'NO reply. Either the SDK dropped the write (serial port not open) or the terminal did not answer. Check the SDK log lines below / in the trace log.',
      'busy' => 'A payment is waiting on the terminal.',
      _ => 'Handshake could not run.',
    };
    return 'GEIDEA TERMINAL STATUS (SDK startCheckStatus over USB)\n'
        'status:  $status\n'
        'elapsed: ${r['elapsedMs'] ?? '-'} ms\n'
        'message: ${r['message'] ?? ''}\n'
        'json:    ${r['json'] ?? ''}\n'
        'raw:     ${r['raw'] ?? ''}\n'
        '=> $verdict\n\n'
        'VERDICT\n${r['verdict'] ?? '-'}\n\n'
        'SIGNAL LADDER (each fact separate)\n${r['ladder'] ?? '-'}\n\n'
        'TIMELINE (ms since the request started)\n${r['timeline'] ?? '-'}\n\n'
        '${await GeideaTerminalBridge.instance.sdkState()}';
  }

  Future<void> _showTextDialog(String title, String text) async {
    var copied = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: SelectableText(
              text,
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: text));
                setDialogState(() => copied = true);
              },
              child: Text(copied ? 'Copied' : 'Copy'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sim = context.watch<SimulatorService>();

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

                  // Simulator toggle — the one manual on/off switch for the
                  // floating dev-tools cluster, same action as the 10-tap
                  // gesture or the cluster's own eye icon. Always live and
                  // always interactive on every build: it used to freeze as
                  // "Always on, can't touch it" when compiled with
                  // ENABLE_SIMULATOR=true, which meant the ONLY way to bring
                  // the cluster back after hiding it via the eye icon was
                  // the 10-tap gesture — needlessly indirect.
                  // LocalPrefs.simulatorForceEnabled only matters for an
                  // ENABLE_SIMULATOR=false build (it's what lets
                  // SimulatorOverlay compile-in at all there); this still
                  // sets it either way, harmlessly, so both build types are
                  // controlled through the same one switch.
                  const Text('Simulator', style: TextStyle(fontWeight: FontWeight.w600)),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Enable simulator dev tools'),
                    subtitle: Text(
                      AppConfig.simulatorAvailable
                          ? 'This build was compiled with ENABLE_SIMULATOR=true — shows/hides the floating cluster.'
                          : 'This build was compiled with ENABLE_SIMULATOR=false; '
                            'turning this on enables and shows the cluster at runtime.',
                    ),
                    value: !sim.devToolsHidden,
                    onChanged: (value) {
                      setState(() => _simForceEnabled = value);
                      LocalPrefs.setSimulatorForceEnabled(value);
                      if (value) {
                        sim.showDevTools();
                      } else {
                        sim.hideDevTools();
                      }
                    },
                  ),

                  // Simulator settings (if available)
                  if (AppConfig.simulatorAvailable || _simForceEnabled) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.settings_remote_outlined),
                      label: const Text('Simulator Settings'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const SimulatorSettingsScreen()),
                      ),
                    ),
                  ],

                  const Divider(height: 32),

                  // Fake payment terminal — lets InvoiceScreen's terminal
                  // payment flow (checkCommunication → session → SDK call
                  // → confirm) be exercised end-to-end with no USB hardware
                  // attached at all: "connected" always true, a payment
                  // always approves after a short fake delay. Deliberately
                  // NOT persisted (see GeideaTerminalBridge.fakeTerminalEnabled's
                  // doc comment) — always off again on the next app launch.
                  const Text('Payment Terminal', style: TextStyle(fontWeight: FontWeight.w600)),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Fake Payment Terminal'),
                    subtitle: const Text(
                      'Testing only — bypasses the real Geidea/USB terminal '
                      'entirely and always reports a connected terminal and '
                      'an approved payment. Resets to off on every app '
                      'restart, never saved.',
                    ),
                    value: _fakeTerminalEnabled,
                    onChanged: (value) {
                      setState(() => _fakeTerminalEnabled = value);
                      GeideaTerminalBridge.fakeTerminalEnabled = value;
                    },
                  ),

                  const Divider(height: 32),

                  // Diagnostic trace logging — writes timestamped lines to
                  // waha_trace.log (native side, see MainActivity.logTrace)
                  // for crash investigation, readable via the separate
                  // "Waha Startup Log" home-screen icon (CrashLogActivity).
                  // Off by default — this shouldn't write to disk forever
                  // on every kiosk in the field. Persisted, so this survives
                  // restart (unlike Fake Payment Terminal above).
                  const Text('Diagnostics', style: TextStyle(fontWeight: FontWeight.w600)),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Enable trace logging'),
                    subtitle: const Text(
                      'Writes startup/crash trace lines to a log file, readable '
                      'via the separate "Waha Startup Log" icon on the home '
                      'screen/app drawer. Off by default — only turn on while '
                      'actively diagnosing an issue.',
                    ),
                    value: _loggingEnabled,
                    onChanged: (value) {
                      setState(() => _loggingEnabled = value);
                      LocalPrefs.setLoggingEnabled(value);
                      TraceLog.setEnabled(value);
                    },
                  ),
                  // Quick access to the trace log without leaving the kiosk app.
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(left: 12),
                    dense: true,
                    leading: const Icon(Icons.description_outlined),
                    title: const Text('Trace log — quick actions'),
                    subtitle: const Text('Open the viewer, upload the log to Waha, or clear it.'),
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: const Icon(Icons.article_outlined),
                        title: const Text('Open log viewer'),
                        onTap: () => GeideaTerminalBridge.instance.openLogViewer(),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: const Icon(Icons.cloud_upload_outlined),
                        title: const Text('Upload log to Waha'),
                        subtitle: const Text('Sends the last ~1 MB of the log; shows a LOG ID to pass on.'),
                        onTap: () => _showDiagnostic('Upload log', _uploadLogText),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: const Icon(Icons.delete_outline),
                        title: const Text('Clear log'),
                        onTap: _confirmClearLog,
                      ),
                    ],
                  ),
                  // A plain row with a chevron, not a switch: tapping it reads
                  // the USB state and opens a dialog with the result.
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.usb),
                    title: const Text('List attached USB devices'),
                    subtitle: const Text(
                      'Shows every USB device, whether this device is a USB '
                      'host or peripheral, and which device the Geidea SDK '
                      'would use. Read-only.',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _showUsbDevices,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.handshake_outlined),
                    title: const Text('Check Geidea Terminal Status'),
                    subtitle: const Text(
                      'Calls the real Geidea startCheckStatus() over USB and '
                      'waits up to 6 s. Shows request started / sent / '
                      'response, the exact SDK result and timing. Unlike '
                      '"Detect", this proves the terminal answers.',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showDiagnostic('Geidea terminal status', _handshakeText),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.fact_check_outlined),
                    title: const Text('Run Full Geidea Diagnostic'),
                    subtitle: const Text(
                      'One complete report (~30 s): USB environment, whether '
                      'the serial port really opens, the real status request '
                      'with timeline, a raw probe of every terminal channel, '
                      'and a verdict on where communication stops. Briefly '
                      'disconnects the SDK — do not run during a payment.',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showDiagnostic(
                      'Full Geidea diagnostic',
                      GeideaTerminalBridge.instance.fullDiagnostic,
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.history_toggle_off),
                    title: const Text('Previous exit reasons'),
                    subtitle: const Text(
                      'Why Android says the app\'s earlier processes ended '
                      '(crash, low memory, force-stop...). Android 11 or newer.',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showDiagnostic(
                      'Previous exit reasons',
                      GeideaTerminalBridge.instance.exitReasons,
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.hub_outlined),
                    title: const Text('SDK internal state & logs'),
                    subtitle: const Text(
                      'What the Geidea SDK believes right now (port open? '
                      'service bound?), its own log lines and log file, and '
                      'the USB inventory. Read-only.',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showDiagnostic(
                      'SDK internal state',
                      GeideaTerminalBridge.instance.sdkState,
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.cable),
                    title: const Text('Probe USB serial channels (raw)'),
                    subtitle: const Text(
                      'Opens each serial channel of the terminal on its own, '
                      'sends the check command and shows which one answers. '
                      'Briefly disconnects the SDK (it reconnects after) — '
                      'do not run during a payment.',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showDiagnostic(
                      'USB channel probe',
                      GeideaTerminalBridge.instance.probeChannels,
                    ),
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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../router/app_router.dart';
import '../screens/camera_scan_screen.dart';
import '../screens/settings_screen.dart';
import '../services/api_exceptions.dart';
import '../services/local_prefs.dart';
import '../state/auth_service.dart';
import '../state/browsing_mode_service.dart';
import '../state/locale_service.dart';
import '../state/order_flow_controller.dart';
import '../state/simulator_service.dart';
import '../state/store_config_service.dart';
import '../utils/locale_name.dart';
import '../utils/scan_actions.dart';
import 'manual_code_dialog.dart';

/// The floating button cluster from the reference screenshot, reworked as
/// tap-targets instead of a settings sub-panel: Close / Home / Settings /
/// Camera / Product. Sits above every screen via a Stack in main.dart, not
/// tied to any one route, so it works regardless of where the user is —
/// which is the point of a dev tool: skip screens, don't require being on
/// the "right" one first.
///
/// Compiled out entirely when AppConfig.simulatorAvailable is false — see
/// that flag's docs on why release builds shouldn't just hide this behind
/// a settings toggle.
class SimulatorOverlay extends StatelessWidget {
  const SimulatorOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    // LocalPrefs.simulatorForceEnabled lets an operator who has already
    // unlocked Settings' Developer Tools panel (10-tap + PIN) turn this back
    // on at runtime even in an ENABLE_SIMULATOR=false build — see its doc
    // comment for why that's a separate flag from AppConfig.simulatorAvailable.
    // Subscribe BEFORE the early return below. Otherwise, in a build without
    // ENABLE_SIMULATOR, this widget never listens to SimulatorService, so
    // flipping "Enable simulator dev tools" in Settings changed the state
    // but nothing redrew the overlay — the toggle looked dead.
    final sim = context.watch<SimulatorService>();
    // The footer has its own switch and shows exactly when that is ON,
    // whether or not the dev-tools cluster is enabled.
    final footerOnly = sim.showFooter
        ? const Stack(children: [_SessionInfoFooter()])
        : const SizedBox.shrink();
    if (!AppConfig.simulatorAvailable && !LocalPrefs.simulatorForceEnabled) {
      return footerOnly;
    }

    // hideDevTools() hides the cluster — secret gesture on mode badge restores.
    if (sim.devToolsHidden) return footerOnly;

    // Footer sits flush at the bottom; the chip/cluster below is pushed up
    // above it when the footer is showing, so the two never overlap.
    final clusterBottom =
        sim.showFooter ? 16.0 + _SessionInfoFooter.height : 16.0;

    if (!sim.clusterVisible) {
      return Stack(
        children: [
          if (sim.showFooter) const _SessionInfoFooter(),
          Positioned(
            bottom: clusterBottom,
            right: 16,
            child: _ReopenChip(onTap: sim.showCluster),
          ),
        ],
      );
    }

    return Stack(
      children: [
        if (sim.showFooter) const _SessionInfoFooter(),
        Positioned(
          bottom: clusterBottom,
          right: 16,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(28),
            color: Colors.black87,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Close and "hide dev tools" are the panel's own meta
                  // controls, always present — not part of the configurable
                  // pinned-buttons set (see SimulatorSettingsScreen).
                  _IconBtn(
                      icon: Icons.close,
                      tooltip: 'Collapse',
                      onTap: sim.hideCluster),
                  _IconBtn(
                    icon: Icons.visibility_off_outlined,
                    tooltip:
                        'Hide all dev tools\n(10-tap the cart screen, or the '
                        'Simulator switch in Settings, to restore)',
                    onTap: sim.hideDevTools,
                  ),
                  if (sim.isPinned(SimPinnedButton.home))
                    _IconBtn(
                      icon: Icons.home,
                      tooltip: 'Home',
                      onTap: () => _goHome(context),
                    ),
                  if (sim.isPinned(SimPinnedButton.settings))
                    _IconBtn(
                      icon: Icons.settings,
                      tooltip: 'Settings',
                      // Straight to the real Settings screen, not the dev
                      // simulator's own — this used to go the other way round
                      // (gear → Simulator Settings → a link out to real
                      // Settings), which was backwards: you want app config
                      // first, dev tooling is the nested, secondary thing, not
                      // the gate you have to walk through to reach it. Scan-code
                      // simulator settings are now reachable *from* Settings
                      // instead — see settings_screen.dart's Developer Tools link.
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const SettingsScreen()),
                      ),
                    ),
                  if (sim.isPinned(SimPinnedButton.camera))
                    _IconBtn(
                      icon: Icons.camera_alt,
                      tooltip: 'Scan with camera',
                      onTap: () => _openCamera(context),
                    ),
                  if (sim.isPinned(SimPinnedButton.productScan))
                    _ScanTypeBtn(
                      type: SimScanType.product,
                      icon: Icons.qr_code,
                      tooltip: 'Product scan',
                    ),
                  if (sim.isPinned(SimPinnedButton.browse))
                    _IconBtn(
                      icon: Icons.grid_view_rounded,
                      tooltip: 'Browse',
                      onTap: () => _goBrowse(context),
                    ),
                  if (sim.isPinned(SimPinnedButton.sessionInfo))
                    _IconBtn(
                      icon: Icons.error_outline,
                      tooltip: 'Toggle session info',
                      onTap: sim.toggleFooter,
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _goBrowse(BuildContext context) {
    Navigator.of(context).pushNamed(Routes.browse);
  }

  void _goHome(BuildContext context) {
    // Dev shortcut: unconditional reset + jump to Landing, regardless of
    // what's mid-flight (mid-scan, non-empty cart, checkout in progress).
    // Not the same action as a real customer-facing "start over" — see
    // OrderFlowController.reset() docs.
    context.read<OrderFlowController>().reset();
    Navigator.of(context).pushNamedAndRemoveUntil(
      Routes.landing,
      (route) => false,
    );
  }

  Future<void> _openCamera(BuildContext context) async {
    final barcode = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const CameraScanScreen()),
    );
    if (barcode != null && context.mounted) {
      await _fireScan(context, barcode);
    }
  }

  static Future<void> _fireScan(
    BuildContext context,
    String code, {
    SimScanType type = SimScanType.product,
  }) async {
    final flow = context.read<OrderFlowController>();

    // Same guard as the real scan paths (scan_actions.dart) — an order placed
    // but not yet paid must block a scan here too, not just from hardware.
    if (flow.orderId != null && flow.order?.status != 'PAID') {
      await showUnpaidOrderBlockedDialog(context);
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    try {
      final product = await flow.scanBarcode(code);
      // Auto-cache hook: covers every simulator trigger (tap-cached,
      // long-press manual entry, camera-via-simulator) from one place, and
      // only caches codes that actually resolved — the point is a library
      // of known-good test codes, not failed attempts.
      if (context.mounted) {
        context.read<SimulatorService>().tryAutoCache(type, code);
      }
      if (LocalPrefs.showScanSuccessToast && context.mounted) {
        final name =
            localeName(product.name, localeService.locale.languageCode);
        messenger.showSnackBar(SnackBar(content: Text('Scanned: $name')));
      }
    } on ProductNotFoundException {
      if (context.mounted) {
        await showBlockingScanError(context, 'No product for code $code');
      }
    } on ProductNotSellableException catch (e) {
      if (context.mounted) await showBlockingScanError(context, e.message);
    } catch (e) {
      if (context.mounted) {
        await showBlockingScanError(context, 'Scan failed: $e');
      }
    }
  }
}

class _ScanTypeBtn extends StatelessWidget {
  final SimScanType type;
  final IconData icon;
  final String tooltip;

  const _ScanTypeBtn(
      {required this.type, required this.icon, required this.tooltip});

  @override
  Widget build(BuildContext context) {
    final sim = context.watch<SimulatorService>();
    return GestureDetector(
      onLongPress: () => _openManualEntry(context),
      child: _IconBtn(
        icon: icon,
        tooltip: '$tooltip (tap: fire cached, long-press: set code)',
        // Tooltip's own long-press-to-show gesture otherwise competes with
        // the GestureDetector above for the same long-press and wins,
        // silently swallowing it before _openManualEntry ever fires.
        tooltipTriggerMode: TooltipTriggerMode.tap,
        onTap: () async {
          final cached = sim.cachedCode(type);
          if (cached == null || cached.isEmpty) {
            // Nothing cached yet — go straight to manual entry rather than
            // firing a blank code or silently doing nothing.
            await _openManualEntry(context);
          } else {
            await SimulatorOverlay._fireScan(context, cached, type: type);
          }
        },
      ),
    );
  }

  Future<void> _openManualEntry(BuildContext context) async {
    final code = await showManualCodeDialog(context, title: 'Set Product Code');
    if (code == null || code.isEmpty) return;
    // Saving to the list now happens inside _fireScan's auto-cache hook
    // (gated by the Cache checkbox/limit), not unconditionally here.
    if (context.mounted) {
      await SimulatorOverlay._fireScan(context, code, type: type);
    }
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final TooltipTriggerMode? tooltipTriggerMode;

  const _IconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.tooltipTriggerMode,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      triggerMode: tooltipTriggerMode,
      child: IconButton(
        icon: Icon(icon, color: Colors.white),
        onPressed: onTap,
      ),
    );
  }
}

/// Bottom info strip — username, store slug, host, app-mode, as a starting
/// set. Whether the whole strip SHOWS AT ALL is SimulatorService.showFooter
/// (cluster button only, see SimulatorOverlay) — that's not this widget's
/// concern. What IS this widget's own concern: the text starts truncated to
/// one line ("Unwrapped" in the reference), and tapping the strip wraps it
/// onto as many lines as it needs ("click to wrap it") — a per-widget expand/
/// collapse of the TEXT, not a show/hide of the strip itself. Non-reactive
/// read of authService/storeConfigService/browsingModeService: it only needs
/// to be current at the moment it's shown, which showing already causes
/// (SimulatorOverlay rebuilds on SimulatorService changes) — good enough for
/// a first cut of a diagnostic-only strip.
class _SessionInfoFooter extends StatefulWidget {
  // Collapsed (one-line) height, kept in sync with the padding/text size
  // below — SimulatorOverlay uses this to keep the button cluster/reopen
  // chip clear of the strip in its normal, collapsed state. Expanding the
  // text (tap) can grow the strip taller than this; the cluster isn't
  // repositioned for that rare, deliberate debug action.
  static const double height = 30;

  const _SessionInfoFooter();

  @override
  State<_SessionInfoFooter> createState() => _SessionInfoFooterState();
}

class _SessionInfoFooterState extends State<_SessionInfoFooter> {
  bool _wrapped = false;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        top: false,
        // Rebuilds when the Custom Connection changes so the host shown here
        // is never stale.
        child: ListenableBuilder(
          listenable: AppConfig.connection,
          builder: (context, _) => _strip(),
        ),
      ),
    );
  }

  Widget _strip() {
    final username = authService.username ?? '—';
    final storeSlug = storeConfigService.storeSlug ?? '—';
    final host = AppConfig.apiBaseUrlLabel;
    final mode = browsingModeService.mode.name;
    final text = 'user:$username  store:$storeSlug  host:$host  mode:$mode';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _wrapped = !_wrapped),
      child: Container(
        constraints: const BoxConstraints(minHeight: _SessionInfoFooter.height),
        width: double.infinity,
        color: Colors.black87,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text(
          text,
          textDirection: TextDirection.ltr,
          overflow: _wrapped ? TextOverflow.visible : TextOverflow.ellipsis,
          softWrap: _wrapped,
          maxLines: _wrapped ? null : 1,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}

class _ReopenChip extends StatelessWidget {
  final VoidCallback onTap;
  const _ReopenChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      shape: const CircleBorder(),
      color: Colors.black54,
      child: IconButton(
        icon: const Icon(Icons.bug_report, color: Colors.white),
        tooltip: 'Show simulator',
        onPressed: onTap,
      ),
    );
  }
}

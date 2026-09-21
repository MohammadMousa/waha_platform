import 'dart:async';
import 'dart:io' show Platform;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'config/app_config.dart';
import 'l10n/generated/app_localizations.dart';
import 'router/app_router.dart';
import 'services/api_client.dart';
import 'services/app_messenger.dart';
import 'services/geidea_terminal_bridge.dart';
import 'services/geidea_usb_activity_logger.dart';
import 'services/local_prefs.dart';
import 'services/server_discovery.dart';
import 'services/trace_log.dart';
import 'services/usb_diagnostics.dart';
import 'state/auth_service.dart';
import 'state/browsing_mode_service.dart';
import 'state/edit_mode_service.dart';
import 'state/locale_service.dart';
import 'state/order_flow_controller.dart';
import 'state/permission_service.dart';
import 'state/simulator_service.dart';
import 'state/store_config_service.dart';
import 'widgets/kiosk_idle_guard.dart';

void main() {
  // Diagnostic-only: catches any uncaught Dart error anywhere in the app
  // (including ones Flutter's own FlutterError.onError below doesn't reach,
  // e.g. inside a Future not awaited by the framework) and forwards it to
  // the same native waha_trace.log MainActivity.logTrace() writes to — see
  // TraceLog and CrashLogActivity. Previously the only logging in this app
  // was native-side (USB/lifecycle events); a Flutter-level crash like a
  // Navigator assertion left zero trace anywhere reachable without adb.
  // Gated by LocalPrefs.loggingEnabled end-to-end (see its doc comment) —
  // TraceLog.log is safe to call unconditionally either way. Remove once
  // the startup crash is root-caused and fixed.
  runZonedGuarded(() async {
    // Needed before touching any platform channel (SharedPreferences included)
    // pre-runApp.
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      TraceLog.log(
        'FlutterError: ${details.exceptionAsString()}\n${details.stack}',
      );
    };

    // Initialize audioplayers audio context on non-web platforms so sounds
    // are routed correctly and not silently discarded by the Android audio system.
    if (!kIsWeb) {
      await AudioPlayer.global.setAudioContext(AudioContext());
    }
    await LocalPrefs.init();
    // Effective = dart-define seeds the persisted flag once on first run,
    // then the Settings toggle is the durable control from then on (same
    // pattern as the dart-define mode fallback below) — OR'd, same
    // philosophy as GeideaTerminalBridge.fakeTerminalEnabled: a true
    // dart-define is a floor the Settings toggle can't turn off, only add
    // to. Tell the native side now so its own next-launch-onward early
    // lines (before Dart can run) already know this value — see
    // TraceLog.setEnabled's doc comment for the one-launch gap this can't
    // close on a fresh install.
    const loggingDefine = bool.fromEnvironment('LOGGING');
    if (loggingDefine && !LocalPrefs.loggingEnabled) {
      await LocalPrefs.setLoggingEnabled(true);
    }
    unawaited(TraceLog.setEnabled(LocalPrefs.loggingEnabled));
    // One shared instance for the app's whole lifetime — not a fresh
    // ApiClient() per use. A separate instance would mean a separate
    // underlying http.Client with its own unwarmed connection pool, so the
    // network warm-up below (and whatever resolveStartupAuth's own calls
    // do) wouldn't carry over to the client screens actually use for
    // checkout/payment. See ApiClient._send's retry comment for the
    // symptom this and the warm-up together are meant to fix.
    final apiClient = ApiClient();
    unawaited(
      apiClient.getConfig().catchError((_) => <String, String>{}),
    ); // fire-and-forget warm-up — pays the DNS/TCP/TLS cost now, not at checkout
    await _resolveStartupConfig(apiClient);
    runApp(WahaApp(apiClient: apiClient));
  }, (error, stack) {
    TraceLog.log('Uncaught zone error: $error\n$stack');
  });
}

/// Applies every persisted/overridden config value once at startup, all
/// with `persist: false` — these are LOADS, not new user choices, so
/// re-writing what was just read back would be redundant at best. The
/// one exception is the dart-define mode fallback: that one DOES persist
/// once applied (see below), so it becomes durable from that point on
/// rather than needing to be re-supplied via --dart-define on every launch.
Future<void> _resolveStartupConfig(ApiClient apiClient) async {
  // Mode: URL override (web, ephemeral, never persisted) > persisted
  // value (survives restart/reboot) > dart-define (first-run seed,
  // becomes persisted from here on) > Kiosk (the constructed default).
  final urlMode = AppConfig.urlOverrideMode;
  if (urlMode != null) {
    browsingModeService.setMode(urlMode, persist: false);
  } else {
    final persistedMode = parseBrowsingMode(LocalPrefs.mode);
    if (persistedMode != null) {
      browsingModeService.setMode(persistedMode, persist: false);
    } else {
      final defineMode = AppConfig.dartDefineMode;
      if (defineMode != null) {
        browsingModeService.setMode(defineMode); // persists — becomes durable
      }
      // else: stays at the BrowsingMode.kiosk it was constructed with.
    }
  }

  final persistedStoreId = LocalPrefs.storeId;
  if (persistedStoreId != null) {
    storeConfigService.setStoreId(persistedStoreId, persist: false);
  }

  final persistedLocale = LocalPrefs.locale;
  if (persistedLocale != null) {
    localeService.setLocale(Locale(persistedLocale), persist: false);
  }

  final beforeWarn = LocalPrefs.beforeWarnSeconds;
  final beforeCountdown = LocalPrefs.beforeCountdownSeconds;
  final afterWarn = LocalPrefs.afterWarnSeconds;
  final afterCountdown = LocalPrefs.afterCountdownSeconds;
  if (beforeWarn != null || beforeCountdown != null || afterWarn != null || afterCountdown != null) {
    kioskTimerConfig.update(
      beforeInvoiceIdleWarningAfter: beforeWarn != null ? Duration(seconds: beforeWarn) : null,
      beforeInvoiceWarningCountdown:
          beforeCountdown != null ? Duration(seconds: beforeCountdown) : null,
      afterInvoiceIdleWarningAfter: afterWarn != null ? Duration(seconds: afterWarn) : null,
      afterInvoiceWarningCountdown:
          afterCountdown != null ? Duration(seconds: afterCountdown) : null,
      persist: false,
    );
  }

  // First-launch auto-discovery: if running on Android with no server
  // address already known — neither a stored one nor a build-time
  // --dart-define=API_BASE_URL — probe the local subnet for a responding
  // backend. If found, save the URL now so resolveStartupAuth below uses
  // the correct host immediately. justDiscoveredUrl bridges the result to
  // LandingScreen for the UI prompt.
  if (!kIsWeb && Platform.isAndroid && !AppConfig.hasExplicitApiBaseUrl) {
    final found = await ServerDiscovery.discover();
    if (found != null) {
      await LocalPrefs.setApiBaseUrl(found);
      ServerDiscovery.justDiscoveredUrl = found;
    } else {
      ServerDiscovery.justDiscoveredUrl = ''; // ran but nothing found
    }
  }

  // Auth resolution — reuses the shared apiClient passed in (see main()'s
  // comment on why that matters for connection warming) rather than a
  // throwaway instance. Implements the specified MVP flow exactly: try
  // cached token, fall back to cached credentials, fall back to a fresh
  // throwaway account for Shopping only. See AuthService.resolveStartupAuth
  // for the full precedence and the failure/timeout handling. Awaited (not
  // fire-and-forget) so the very first frame already reflects whether
  // there's a session, rather than flashing a logged-out state for a
  // moment first. Mode must already be resolved by this point — Shopping's
  // auto-account behavior depends on it.
  await authService.resolveStartupAuth(apiClient, browsingModeService.mode);

  // Geidea USB terminal (card-present payment) — Kiosk-only, matching
  // payment_methods.available_modes for the 'terminal' row. Fire-and-forget:
  // USB connection is inherently async/best-effort (the terminal may not be
  // plugged in yet, or this may be a dev device with no hardware at all)
  // and shouldn't block or fail app startup either way.
  if (browsingModeService.mode == BrowsingMode.kiosk) {
    unawaited(GeideaTerminalBridge.instance.initialize());
    UsbDiagnostics.logSnapshot('app start');
  }
}

class WahaApp extends StatelessWidget {
  final ApiClient apiClient;
  const WahaApp({required this.apiClient, super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // .value, not create: (_) => ApiClient() — reuses the same
        // instance main() already warmed a connection on, instead of a
        // fresh one with its own cold connection pool.
        Provider.value(value: apiClient),
        ChangeNotifierProvider(
          create: (context) => OrderFlowController(context.read<ApiClient>()),
        ),
        ChangeNotifierProvider(create: (_) => SimulatorService()),
        ChangeNotifierProvider.value(value: editModeService),
        ChangeNotifierProvider.value(value: storeConfigService),
        ChangeNotifierProvider.value(value: browsingModeService),
        ChangeNotifierProvider.value(value: localeService),
        ChangeNotifierProvider.value(value: authService),
        ChangeNotifierProvider.value(value: permissionService),
      ],
      // Builder, not MaterialApp directly — MaterialApp needs a context
      // BELOW MultiProvider's providers to `watch` LocaleService for the
      // `locale:` param; WahaApp.build's own context is above them.
      child: Builder(
        builder: (context) {
          final locale = context.watch<LocaleService>().locale;
          return GeideaUsbActivityLogger(
            // Mounted once for the app's whole lifetime, wrapping
            // MaterialApp itself — NOT per-route. See kiosk_idle_guard.dart's
            // doc comment for why: a per-route instance let two guarded
            // routes stacked on top of each other run two independent idle
            // timers at once, a confirmed real cause of a black-screen
            // crash. This single instance tracks the current route via
            // KioskRouteObserver below and acts through navigatorKey.
            child: KioskIdleGuard(
              child: MaterialApp(
                title: 'Waha Kiosk',
                debugShowCheckedModeBanner: false,
                theme: ThemeData(
                  colorSchemeSeed: const Color(0xFF6B1A2A),
                  useMaterial3: true,
                ),
                locale: locale,
                supportedLocales: const [Locale('en'), Locale('ar')],
                localizationsDelegates: const [
                  AppLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                scaffoldMessengerKey: rootScaffoldMessengerKey,
                navigatorKey: navigatorKey,
                navigatorObservers: [KioskRouteObserver()],
                onGenerateRoute: onGenerateRoute,
                initialRoute: Routes.landing,
                // No `builder` override here on purpose — the simulator overlay
                // is stacked per-route inside onGenerateRoute instead, so it
                // lives inside the Navigator's Overlay. See app_router.dart.
              ),
            ),
          );
        },
      ),
    );
  }
}

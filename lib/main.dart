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
import 'services/local_prefs.dart';
import 'services/server_discovery.dart';
import 'state/auth_service.dart';
import 'state/browsing_mode_service.dart';
import 'state/edit_mode_service.dart';
import 'state/locale_service.dart';
import 'state/order_flow_controller.dart';
import 'state/permission_service.dart';
import 'state/simulator_service.dart';
import 'state/store_config_service.dart';

Future<void> main() async {
  // Needed before touching any platform channel (SharedPreferences included)
  // pre-runApp.
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize audioplayers audio context on non-web platforms so sounds
  // are routed correctly and not silently discarded by the Android audio system.
  if (!kIsWeb) {
    await AudioPlayer.global.setAudioContext(AudioContext());
  }
  await LocalPrefs.init();
  await _resolveStartupConfig();
  runApp(const WahaApp());
}

/// Applies every persisted/overridden config value once at startup, all
/// with `persist: false` — these are LOADS, not new user choices, so
/// re-writing what was just read back would be redundant at best. The
/// one exception is the dart-define mode fallback: that one DOES persist
/// once applied (see below), so it becomes durable from that point on
/// rather than needing to be re-supplied via --dart-define on every launch.
Future<void> _resolveStartupConfig() async {
  // Mode: URL override (web, ephemeral, never persisted) > persisted
  // value (survives restart/reboot) > dart-define (first-run seed,
  // becomes persisted from here on) > Normal.
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
      // else: stays at the BrowsingMode.normal it was constructed with.
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

  // First-launch auto-discovery: if running on Android with no URL stored,
  // probe the local subnet for a responding backend. If found, save the URL
  // now so resolveStartupAuth below uses the correct host immediately.
  // justDiscoveredUrl bridges the result to LandingScreen for the UI prompt.
  if (!kIsWeb && Platform.isAndroid && LocalPrefs.apiBaseUrl == null) {
    final found = await ServerDiscovery.discover();
    if (found != null) {
      await LocalPrefs.setApiBaseUrl(found);
      ServerDiscovery.justDiscoveredUrl = found;
    } else {
      ServerDiscovery.justDiscoveredUrl = ''; // ran but nothing found
    }
  }

  // Auth resolution — a standalone ApiClient here since this runs before
  // the Provider tree exists. Implements the specified MVP flow exactly:
  // try cached token, fall back to cached credentials, fall back to a
  // fresh throwaway account for Shopping only. See
  // AuthService.resolveStartupAuth for the full precedence and the
  // failure/timeout handling. Awaited (not fire-and-forget) so the very
  // first frame already reflects whether there's a session, rather than
  // flashing a logged-out state for a moment first. Mode must already be
  // resolved by this point — Shopping's auto-account behavior depends on it.
  await authService.resolveStartupAuth(ApiClient(), browsingModeService.mode);
}

class WahaApp extends StatelessWidget {
  const WahaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider(create: (_) => ApiClient()),
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
          return MaterialApp(
            title: 'Waha',
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
            onGenerateRoute: onGenerateRoute,
            initialRoute: Routes.landing,
            // No `builder` override here on purpose — the simulator overlay
            // is stacked per-route inside onGenerateRoute instead, so it
            // lives inside the Navigator's Overlay. See app_router.dart.
          );
        },
      ),
    );
  }
}

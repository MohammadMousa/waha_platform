# Waha Platform — Flutter Frontend

Flutter frontend for Waha, a self-service kiosk and retail shopping system. Consumes the [Waha backend](https://github.com/mohammad_mousa79/waha) REST API.

## Modes

| Mode | Description |
|---|---|
| **Normal** | Full-featured retail app — browse, search, cart, orders, profile |
| **Kiosk** | Locked-down self-service terminal — scan, cart, checkout, idle reset |
| **Shopping** | Guest-friendly mobile shopping — no login required, guest session auto-created |

Mode is set via `POST /api/auth/store` with `sessionProperties: {"mode": "KIOSK"}` and persisted locally.

## Stack

- Flutter (Dart) — cross-platform: Android, iOS, Linux desktop (kiosk)
- Provider — state management
- `flutter_localizations` + ARB — full Arabic / English localization (RTL-aware)
- `shared_preferences` — local token + config persistence

## Project structure

```
lib/
├── config/         AppConfig — base URL, dart-define overrides
├── l10n/           ARB localization files (app_en.arb, app_ar.arb) + generated
├── models/         AuthSession, Product, Quote, CartItem, Order, Store ...
├── router/         Named route definitions
├── screens/        One file per screen
├── services/       ApiClient (HTTP), LocalPrefs (SharedPreferences)
├── state/          AuthService, OrderFlowController, PermissionService,
│                   StoreConfigService, BrowsingModeService, LocaleService
├── utils/          localeName, scanActions, price formatting
└── widgets/        Reusable widgets — WahaAppBar, WahaBottomNav, CartLineTile,
                    ProductImage, CheckoutBar, ProductDetailSheet ...
```

## Running locally

```bash
# Point at the local backend
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080
```

- Android emulator → `http://10.0.2.2:8080`
- iOS simulator / desktop → `http://localhost:8080`
- Physical device on LAN → the machine's LAN IP

## Localization

ARB files live in `lib/l10n/`. After editing them, regenerate:

```bash
flutter gen-l10n
```

Generated files go to `lib/l10n/generated/` — do not edit those by hand.

## Roles & permissions

Permissions are resolved server-side per user+store and returned in every auth response. The `PermissionService` singleton caches them and exposes `can('PERMISSION_NAME')` for UI gating. Backend always re-enforces — a bypassed UI check results in a 403, not a breach.

Role hierarchy: `SUPER_ADMIN > ADMIN > OPERATOR > CASHIER > REGISTERED > ANONYMOUS`

# Waha Kiosk — Flutter client

## Important: this hasn't been compiled or run

This was written in a sandbox with no Flutter SDK and no network access —
I couldn't run `flutter create`, `flutter pub get`, or `flutter analyze`
against it. The Dart is written carefully and checked by hand for balanced
braces/parens, but it has **not** gone through a real analyzer or compiler.
Run `flutter analyze` yourself as the very first step before assuming
anything here is correct. Three dependencies added since the first round
and equally unverified: `shared_preferences`, `qr_flutter` (the Success
screen's e-invoice QR), and `url_launcher` (opening the real payment
redirect in an external tab/window) — same caveat applies to all three.

## One-time setup (do this locally, in IntelliJ or a terminal)

```bash
flutter create --platforms=android,web,windows,macos,linux waha_kiosk
```

This generates the platform boilerplate (`android/`, `web/`, etc.) that
can't be hand-written reliably — let the real tool produce it. Then:

1. Delete the generated `lib/` and `pubspec.yaml`.
2. Copy this `lib/` folder, this `pubspec.yaml`, **and `l10n.yaml`**
   (project root, not inside `lib/` — easy to miss) into that project.
3. `flutter pub get`

## Localization (EN/AR)

Strings live in `lib/l10n/app_en.arb` and `lib/l10n/app_ar.arb`. Because
`generate: true` is set in `pubspec.yaml`, `flutter pub get` (and
`flutter run`) auto-generates `lib/l10n/generated/app_localizations.dart`
from those ARB files — nothing to run by hand, but if that generated file
is ever missing, `flutter gen-l10n` produces it directly. If step 2 above
skips `l10n.yaml`, codegen either doesn't run or runs with defaults that
won't match the `import '../l10n/generated/app_localizations.dart'`
paths used throughout the app — that's the one file outside `lib/` this
project actually needs.

Coverage: Landing, Scan's shared capture field, Cart (incl. empty state
and the checkout bar), Pay, Success, Settings, and Profile are fully
localized. Deliberately left in English: the transient Checkout
loading/retry screen, Scan screen's own chrome ("No items scanned yet",
"View Cart (n)"), and every dev-only screen (Simulator Settings, the
debug lock-test stub, camera scan's on-screen hints) — translating
internal tooling didn't seem worth the scope expansion, but the pattern's
established if that changes.

## Running against the backend

```bash
# Android emulator (talks to host machine's localhost via the special alias)
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080

# Web
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080

# Real device on the same LAN as the backend
flutter run --dart-define=API_BASE_URL=http://<backend-lan-ip>:8080
```

If you omit `API_BASE_URL`, `AppConfig` falls back to the same defaults
FRONTEND_CONTEXT.md specifies per platform — see `lib/config/app_config.dart`.

Force a specific mode independent of platform, useful for testing a
mode's behavior on a build where it isn't normally used (Settings also
lets you do this at runtime — see below):

```bash
flutter run --dart-define=APP_MODE=kiosk
```

On web, the real-world way Shopping mode gets entered is a URL query
param, not a rebuild — e.g. a kiosk shows a QR/link containing
`?mode=shopping`, and the customer lands straight in the restricted flow
on their own phone:

```
https://your-deployed-url/?mode=shopping
```

To build a release with the simulator compiled out entirely:

```bash
flutter build apk --dart-define=ENABLE_SIMULATOR=false
```

## Persistence

Mode, store id, kiosk username, and kiosk timers all survive an app
restart or device reboot now (`shared_preferences`) — this used to be
in-memory only, which meant a kiosk losing power came back up in Normal
mode with navigation unlocked. Resolution order at every startup:

1. Web only: a `?mode=` URL query param — ephemeral, never persisted
   (a Shopping QR link shouldn't permanently convert that browser)
2. Whatever's persisted from a previous run/Settings change
3. `--dart-define=APP_MODE=...` — only as a first-run seed; becomes
   persisted from that point on
4. Normal, otherwise

Store id and kiosk username follow the same shape without the URL-param
step (`--dart-define=STORE_ID=...` as the first-run seed, Settings for
everything after).

## What's built

- Full Landing → Scan → Cart → Checkout → Pay → Success flow against every
  endpoint in FRONTEND_CONTEXT.md, with typed 404/409 handling per
  endpoint and decline-as-normal-outcome on `/pay`
- UUID **v7** order id minted client-side (not v4 — the backend clusters
  `orders.id` on it), reused on retry (idempotent create); cart cleared
  client-side right after a successful order create, and on every point
  where store context can change (Settings, login, store picker)
- Real auth — register/login/logout/me/select-store, one identity
  mechanism for every mode: Kiosk is provisioned once by an operator
  (real login) and never logs out from a restricted session; Shopping
  auto-registers a throwaway account on first launch with no usable
  cached session; Normal stays anonymous until Checkout gates on a real
  login, redirecting there and back via a return-to-target argument
  chain (Checkout → Login → StorePicker if needed → back to Checkout)
- Startup auth resolution matches the specified MVP flow exactly: cached
  token first (verified via `/me`, 5s timeout) → cached credentials
  re-authenticated if the token's rejected/expired → a fresh guest
  account for Shopping only if neither works → logged out otherwise. No
  refresh-token endpoint exists in the contract — credentials are cached
  alongside the token per explicit direction (see the plaintext-storage
  note in `LocalPrefs` and `BACKEND_CONTEXT.md`)
- Real product browsing (`GET /api/products`, paginated), each row with
  a quick-add action (no "customizable product" concept exists server-side
  yet, so nothing forces a detour through Product Detail before adding);
  Stores screen (`GET /api/stores`) reachable from the header any time,
  not just via the login chain — works logged in (`POST /api/auth/store`,
  session-bound) or logged out (sets the local fallback instead), with an
  explicit "Set as Default" action per row independent of that
- `storeId`: session-resolved (omitted) for a logged-in customer with a
  selected store, explicit (device-configured, defaulting to `0` — see
  BACKEND_CONTEXT.md item 9) otherwise — one decision point
  (`OrderFlowController`), not re-derived per screen. `username` is
  never sent explicitly anymore — every mode resolves it through
  AuthService now
- Real payment for Normal/Shopping — Stripe/MyFatoorah via
  `POST /api/orders/{id}/payment-session`, opened in an external tab/
  window (`url_launcher`), with the app polling `GET /api/orders/{id}`
  every 2s until `PAID` rather than trusting the redirect landing itself
  (per FRONTEND_CONTEXT.md's explicit warning that assuming so is wrong
  on the happy path). Kiosk keeps the original simulated synchronous
  `/pay` flow, unchanged — genuinely different endpoints, not two modes
  of one flow
- Real e-invoice QR on the Success screen — encodes the order's real
  `invoiceUrl` (via `qr_flutter`), not a placeholder or a client-built URL
- Three browsing modes — Normal (full navigation, same on every
  platform), Kiosk (android/desktop, locked navigation + idle-recovery
  timers), Shopping (web, locked navigation, no timers) — encoded as one
  enum tagging each mode with which platform(s) it's normally used on,
  not three independent options; Settings' mode picker is filtered by
  that instead of offering Kiosk and Shopping side by side
- Kiosk-only two-context idle-recovery timers (before/after invoice),
  each with its own configurable warn-after delay and countdown,
  editable from Settings — the after-invoice context now wraps a real QR
  screen instead of a placeholder
- Mode-aware scan entry: Kiosk captures hardware-scanner input ambiently
  right on Landing (invisible, always-focused field — no visible "go
  scan" step); Shopping opens the camera directly since a phone browser
  has no hardware scanner; Normal reaches the manual/hardware Scan
  screen explicitly via the header
- Camera scan screen: scan-target frame overlay (visual only, doesn't
  affect `mobile_scanner` detection) and a confirmed "Clear All" cart action
- Real Settings screen (language, store id fallback, mode picker, kiosk
  timer fields) separate from the dev-only Simulator Settings
  (scan-code simulator, compiled out via `ENABLE_SIMULATOR=false`) —
  Settings links *into* Simulator Settings via a Developer Tools section,
  not the other way round
- Always-visible mode badge (bottom-left, every screen) — current mode
  at a glance without opening Settings
- `ProfileScreen` — real session state (logged in as / selected store /
  logout) or a login/register prompt, not a placeholder
- EN/AR localization via standard `flutter gen-l10n` codegen — see
  "Localization" above for exact screen coverage
- Simulator overlay: Close / Home / Settings / Camera / Product-scan, with
  tap-fires-cached / long-press-sets-code, falling through to manual entry
  when nothing's cached yet

## What's deliberately not built

- Coupon/wallet simulation (no backend contract for them yet)
- Admin cycles (explicitly deferred)
- An actual Kiosk provisioning UI (store/gateway/initial-sync/test setup
  wizard) — Kiosk now supports being pre-logged-in via the same real
  auth as everyone, but who/what walks an operator through that setup is
  a separate question, explicitly out of scope for this round
- An operator escape hatch to get a Kiosk device back into Normal mode
  for reconfiguration in the field (PIN, long-press, etc.) — the dev
  Simulator Settings link stands in for this during testing only
- Actual offline operation (local order queue, sync/retry on reconnect)
  — still Phase 4; the design principle behind it is now on record
  (BACKEND_CONTEXT.md item 6) but nothing's built toward it
- Browse/Product Detail reachable from Shopping mode (MVP.txt's table
  says it should be) — deliberately scoped to Normal mode only so far,
  to avoid touching Shopping's already-built fast-scan flow in the same
  change
- Anything under "Explicitly not built yet" in FRONTEND_CONTEXT.md that
  the MVP update didn't cover — digital product catalog, real payment,
  offline queue, phone number collection, kiosk fleet/device management

## Open questions carried over from design discussion (not resolved in code)

- Cart screen's behavior when `/quote` returns 409 mid-shopping (item went
  unsellable after being scanned): currently the item stays in the cart and
  the error banner shows — nobody's confirmed whether it should instead be
  auto-removed. See the comment in `order_flow_controller.dart`.
- Simulator's release-build story: `ENABLE_SIMULATOR` is a compile-time
  `--dart-define`, not the on-device Settings toggle the reference
  screenshot showed — that was flagged earlier as a real leak risk if it's
  just a runtime setting.

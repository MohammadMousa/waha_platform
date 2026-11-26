# Architecture

How the kiosk app starts, signs in, finds its server and moves between screens.

---

## Parts

| Layer | Where | Role |
|---|---|---|
| Screens and widgets | `lib/screens/`, `lib/widgets/` | What the customer and the operator see |
| State | `lib/state/` | Device sign-in, cart and order, store, language, timers, permissions |
| Services | `lib/services/` | Server API, terminal bridge, restart, heartbeat, logging, scanner |
| Local data | `lib/data/` | Database, sync, local orders, resource cache. See [offline-sync.md](offline-sync.md) |
| Android native | `android/app/src/main/kotlin/com/waha/kiosk/` | Geidea SDK, USB diagnostics, logs, crash handling, restart |

State is shared with Provider. `main.dart` creates **one `ApiClient`** for the whole app, so every screen uses the same warmed connection. The native side is reached through the `com.waha/geidea` channel, with a separate channel for terminal events and one for USB diagnostics.

---

## Startup

1. Load saved settings, app information and the connection setting. Apply the logging state and start the restart timer.
2. Load the saved store, language and idle timers.
3. Check that the server answers (`GET /api/config`, 5 s).
4. **Server answers:** sign in with the saved device token.
5. **Server does not answer:** open from the saved session if there is one. If not, show the connection popup.
6. Start the terminal SDK without waiting for it, then the late-approval, heartbeat and sync services.

A payment, sync or terminal problem does not stop the app from starting.

### Connection popup

It blocks the app until the server answers. It retries after 10 s, then doubles the wait up to 5 minutes. It shows details for support and a **Retry now** button. When a custom connection is on, it can also edit it or return to the default server.

The app never changes server by itself.

---

## Device sign-in

The kiosk has one identity: a **device account** (username and PIN) created in the dashboard. There are no customer accounts or guest sign-in.

| Rule | Detail |
|---|---|
| What is saved | The token, the username and a copy of the session details. **The PIN is never saved** |
| Each start | The token is checked with `GET /api/kiosk/auth/me` |
| Token rejected | It is removed and the Device Login screen shows |
| Server cannot be reached | The token is kept. Only a real rejection signs the device out |
| Sign out | `cmd=profile`, then the PIN. If the server cannot be reached, the device stays signed in |

**Store.** It comes from the device account. A new sign-in clears the previous store.

**PIN check.** The server checks the PIN (`POST /api/kiosk/auth/pin/verify`), so opening a PIN-protected screen needs the server.

---

## Server connection

The address is chosen in this order:

1. **Custom Connection**, when it is on and its address is valid.
2. `API_BASE_URL` set when the app was built.
3. A platform default for development. On Android this is the emulator address, which a real device cannot reach.

Turning Custom Connection off keeps its saved fields.

**Changing server** is safe by design. The app first checks the new server and signs in there with a separate client. Only if both work does it end the old session, clear the session, store, landing page details and cart, and switch. A failure leaves everything as it was. The operator needs a device login that works on the new server.

The change does not clear the local database. Check for orders waiting to be sent before changing server.

---

## Screens

The app is always a kiosk.

| Route | Screen |
|---|---|
| `/` | Landing page |
| `/cart` | Cart |
| `/checkout` | Creates the order, then opens the invoice |
| `/invoice` | Invoice and payment. See [payments.md](payments.md) |
| `/browse`, `/categories`, `/search` | Catalog |
| `/scan`, `/success` | Allowed, but no code opens them by name |
| `/settings` | Settings |
| `/kiosk-login` | Device Login |

**Route guard:** without a device session, every route shows Device Login. A route outside the allowlist shows the landing page.

**Main flow:** landing → cart → checkout → invoice → paid dialog → landing. A scan or an added item on the landing page opens the cart. The order is created on checkout and the cart is then emptied. If creation fails, the cart stays and the same order id is used on retry.

**Going home:** use `goHomeKeepingLanding`. It returns to the existing landing page and avoids rebuilding its WebView, which shows a blank screen on the kiosk.

---

## Scanning

The hardware scanner types like a keyboard. A listener is added to the catalog, cart and payment screens, not to Settings. Only the top listener handles a scan. The camera and the simulator use the same entry point, `ScannerManager.handle`. See [device-operations.md](device-operations.md#admin-commands-qr).

---

## Idle guard

**One guard for the whole app**, set up above the navigator. Do not add one per screen: two timers once caused a black screen crash.

- It can be turned off with "Enable Idle Timers" in Settings.
- Every screen except the landing page is timed. After the idle time it shows a countdown. No answer resets the order and returns home.
- Touches and scanner keys count as activity.
- It is held back while a payment dialog is open and after an order is paid. The paid dialog has its own countdown.
- An unpaid invoice uses the "before invoice" time.

Each of the four timer values (idle time and countdown, before and after invoice) defaults to 60 s.

---

## Server properties

`GET /api/config?orgId=` returns the organization's properties. The app saves the last good answer. A failed request changes nothing.

The kiosk reads them at startup, and again with the periodic landing page check, which starts once a token and a store are ready: first after 30 s, then every `check_landing_page_interval_minutes` (default 30, 1 to 1440). Sync also reads them before each pull.

| Topic | Where the properties are listed |
|---|---|
| Logging, uploads, restart, heartbeat | [device-operations.md](device-operations.md) |
| Terminal timeout | [payments.md](payments.md#timeout-result-unknown) |
| Offline, sync, cleanup, cache | [offline-sync.md](offline-sync.md#server-properties) |

Also read: `appName`, `default_language` (used only while the device has no language choice of its own) and `prices_exclude_vat`.

---

## Language

Arabic and English, with right-to-left layout. See the README for how to edit the text files.

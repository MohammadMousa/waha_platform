# Waha Platform — Flutter Frontend

Flutter frontend for Waha, a multi-store retail and self-service kiosk system. Consumes the [Waha backend](https://github.com/mohammad_mousa79/waha) REST API.

## Stack

- **Flutter / Dart** — Android, iOS, Linux desktop (kiosk), Web
- **Provider** — state management
- `flutter_localizations` + ARB — full Arabic / English localisation, RTL-aware
- `shared_preferences` — token, store, and mode persistence across restarts
- `webview_flutter` — HTML landing pages, in-app WebView
- `printing` / `pdf` — client-side PDF generation fallback

## Running locally

```bash
# Android emulator
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080

# iOS simulator or desktop
flutter run --dart-define=API_BASE_URL=http://localhost:8080

# Physical device or kiosk on LAN
flutter run --dart-define=API_BASE_URL=http://192.168.1.x:8080

# Web
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080
```

---

## Modes

The app runs in one of three browsing modes, set at login via `sessionProperties` and persisted locally.

| Mode | Who uses it | Behaviour |
|------|-------------|-----------|
| **Normal** | Store staff, admin | Full app — browse, search, cart, orders, profile, admin panel |
| **Shopping** | Customer's own phone | Guest-friendly — no login required, guest session auto-created |
| **Kiosk** | Self-service terminal | Locked navigation, idle guard, scan-only entry point |

Mode is stored in `BrowsingModeService` and drives: which nav items appear, whether the idle guard is active, and which screens are reachable from kiosk links (allowlist: browse, categories, search, product detail).

---

## Key features

### Catalog & shopping
- **Browse** — paginated product grid, category filter, infinite scroll
- **Search** — full-text across product names and tags
- **Product detail sheet** — avatar, scrollable gallery strip, description, tags, add-to-cart
- **Cart** — quantity stepper per product, live server-computed quote
- **Barcode / QR scan** — camera scan or manual entry, kiosk hardware scan via keyboard input intercept

### Checkout & payment
- **Simulated payment** — instant success/failure, useful for demos and testing
- **QR payment** — kiosk shows QR, customer scans on their phone; SSE stream auto-closes when confirmed
- **Redirect payment** — Stripe Checkout / MyFatoorah hosted page (opens in browser)
- **Terminal payment** — card-present EMV flow via backend terminal session API
- **Invoice screen** — live payment status, bilingual HTML rendered in WebView, PDF download

### Admin panel (Normal mode, ADMIN / OPERATOR)
- **Edit mode toggle** — overlay edit buttons appear on products and categories in-place; toggled via app bar button
- **Product edit** — avatar, gallery images, bilingual name/description, tags (chip input)
- **Category edit** — bilingual name, avatar image
- **Store edit** — display name, currency, avatar image, payment method toggles
- **Store management** — list all stores in admin subtree, create new store, switch active store
- **Resource file manager** — directory tree, upload single file or batch, rename, move, delete; HTML preview via WebView (native) or new tab (web); image preview with layout toggle
- **Receipt info edit** — store receipt header, bilingual invoice titles
- **Payment methods** — enable/disable per store (Simulated, QR, Stripe, MyFatoorah, Terminal)
- **Odoo integration panel** — configure URL/key/database, pull categories + products, push orders

### Landing pages
- HTML pages served from the store's resource library (`pages/` directory) rendered in-app via WebView
- Absolute paths resolved at load time; language toggled without reload
- Banner links (`href="/screen?name=browse_screen&tag=TAG"`) intercepted — navigate to browse/search inside the app; works in kiosk mode

### Kiosk-specific
- **Idle guard** — configurable inactivity timer, full-screen overlay with countdown; tap to extend, auto-reset to home
- **Locked navigation** — back gestures and drawer hidden; only allowlisted routes reachable
- **Language toggle** — visible in kiosk and shopping modes
- **Dev tools toggle** — hidden tap target in kiosk mode for quick access to settings

---

## Project structure

```
lib/
├── config/
│   └── app_config.dart          API base URL (dart-define override)
├── l10n/
│   ├── app_en.arb               English strings
│   ├── app_ar.arb               Arabic strings
│   └── generated/               flutter gen-l10n output — do not edit
├── models/
│   ├── auth_session.dart        Token, user info, permissions, store
│   ├── cart_item.dart
│   ├── category.dart
│   ├── order.dart
│   ├── payment_method.dart
│   ├── pay_result.dart
│   ├── product.dart             name/description bilingual JSON, gallery IDs, tags
│   ├── product_page.dart        Paginated product list response
│   ├── quote.dart
│   └── store.dart
├── router/
│   └── app_router.dart          Named routes + argument types
├── screens/
│   ├── browse_screen.dart       Product grid — category filter, search query, infinite scroll
│   ├── camera_scan_screen.dart  Camera barcode scan
│   ├── cart_screen.dart
│   ├── categories_screen.dart
│   ├── category_edit_screen.dart
│   ├── checkout_screen.dart
│   ├── invoice_screen.dart      HTML invoice in WebView + PDF
│   ├── landing_screen.dart      HTML landing page in WebView with banner interception
│   ├── login_screen.dart
│   ├── odoo_admin_screen.dart
│   ├── orders_screen.dart
│   ├── payment_methods_screen.dart
│   ├── pay_screen.dart
│   ├── product_detail_screen.dart
│   ├── product_edit_screen.dart  Avatar, gallery, name, description, tags
│   ├── profile_screen.dart
│   ├── qr_payment_screen.dart    QR dialog with SSE countdown
│   ├── receipt_info_edit_screen.dart
│   ├── register_screen.dart
│   ├── resource_explorer_screen.dart  File manager
│   ├── resource_picker_modal.dart     Resource picker for image selection
│   ├── scan_screen.dart
│   ├── search_screen.dart
│   ├── settings_screen.dart
│   ├── store_edit_screen.dart
│   ├── store_picker_screen.dart
│   └── success_screen.dart
├── services/
│   ├── api_client.dart          All HTTP calls — single source of truth
│   ├── api_exceptions.dart      Typed exceptions (ApiException, NetworkException, …)
│   ├── landing_cache.dart       Landing page HTML cache + absolute path resolver
│   ├── local_prefs.dart         SharedPreferences wrapper
│   ├── scan_sound_service.dart  Beep on barcode scan
│   └── server_discovery.dart    LAN server discovery
├── state/
│   ├── auth_service.dart        Token, login/logout, store selection
│   ├── browsing_mode_service.dart  Normal / Shopping / Kiosk
│   ├── edit_mode_service.dart   Edit overlay toggle (admin only)
│   ├── locale_service.dart      AR / EN toggle
│   ├── order_flow_controller.dart  Cart, quote, active order
│   ├── permission_service.dart  can('PERMISSION_NAME') gating
│   ├── simulator_service.dart   Dev simulator controls
│   └── store_config_service.dart   Active store — id, slug, currency, display name
└── widgets/
    ├── admin_drawer.dart         Admin navigation drawer
    ├── batch_upload_dialog.dart  Multi-file upload progress
    ├── cart_line_tile.dart
    ├── checkout_bar.dart
    ├── edit_mode_toggle.dart     App bar toggle button
    ├── kiosk_idle_guard.dart     Inactivity overlay
    ├── product_detail_sheet.dart  Bottom sheet — loads full detail async (gallery, tags)
    ├── product_image.dart        Image with loading spinner + placeholder
    ├── quantity_stepper.dart     Animated +/qty/− pill
    ├── resource_picker_sheet.dart  Camera / Gallery / Resource Manager chooser
    ├── save_resource_dialog.dart  Upload + name a new resource
    ├── scan_capture_field.dart   Hardware scanner keyboard intercept
    ├── waha_app_bar.dart
    └── waha_bottom_nav.dart
```

---

## Roles & permissions

Permissions are resolved server-side per user + store and returned in every auth response. `PermissionService` caches them locally and exposes `can('PERMISSION_NAME')` for UI gating. The backend always re-enforces — a bypassed UI check results in a 403.

| Role | Default capabilities |
|------|---------------------|
| `SUPER_ADMIN` | Everything |
| `ADMIN` | Catalog, resources, store management, users |
| `OPERATOR` | Catalog editing, resource management |
| `CASHIER` | Order viewing and processing |
| `REGISTERED` | Browse, own orders |
| `ANONYMOUS` | Browse (guest session) |

Key permissions used for UI gating:

| Permission | Gates |
|------------|-------|
| `EDIT_PRODUCTS` | Edit mode toggle, product edit button |
| `MANAGE_CATEGORIES` | Category edit button |
| `EDIT_RESOURCES` | File manager upload/rename/delete |
| `MANAGE_STORES` | Store management, store creation, edit store |

---

## Localization

ARB files live in `lib/l10n/`. After editing, regenerate:

```bash
flutter gen-l10n
```

Generated files go to `lib/l10n/generated/` — do not edit by hand. The active locale is managed by `LocaleService` and can be toggled at runtime (kiosk and shopping modes show a language button in the app bar).

---

## Product images

`ProductImage` widget handles all product, category, and store avatar display:
- Shows a two-ring loading spinner while the image loads
- Falls back to a tinted placeholder on error or when `imageResourceId` is null
- URL is `{API_BASE_URL}/api/resources/{imageResourceId}` — served directly from the backend

Gallery images in the product detail sheet are loaded as a horizontal strip via the same widget.

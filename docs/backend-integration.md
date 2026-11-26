# Backend integration

Which backend APIs the kiosk uses.

**This page does not define the APIs.** Request and response contracts belong to the [Waha backend](https://github.com/MohammadMousa/waha) repository. Update this list when the app starts or stops using a call.

---

## Calls

### Server and device

| Call | Used for |
|---|---|
| `GET /api/config` | Reachability check and server properties |
| `POST /api/kiosk/auth/login` | Device sign-in |
| `GET /api/kiosk/auth/me` | Checking the saved token |
| `POST /api/kiosk/auth/pin/verify` | Device PIN |
| `POST /api/kiosk/auth/logout` | Sign-out |
| `POST /api/auth/logout` | Ending a user session that is not a device session |
| `POST /api/kiosk/heartbeat` | Sign of life |
| `GET /api/stores` | Store name and currency |

### Catalog

| Call | Used for |
|---|---|
| `GET /api/products/barcode/{barcode}` | A scan |
| `GET /api/products` | Browsing, with an optional category |
| `GET /api/products/search` | Search |
| `GET /api/products/{id}` | Product details |
| `GET /api/categories` | Categories |

In `caching` mode the app adds `full=1` to product reads, to save complete products.

### Orders and payments

| Call | Used for |
|---|---|
| `GET /api/payment-methods` | Methods for the store, `mode=KIOSK` |
| `POST /api/orders/quote` | Cart prices, offers and coupons |
| `POST /api/orders` | Creating an order |
| `GET /api/orders/{id}` | Order status |
| `GET /api/orders/{id}/payment-events` | Live payment signal during a QR link payment |
| `POST /api/orders/{id}/payment-session` | QR payment link |
| `POST /api/orders/{id}/terminal-session` | Starting a card payment |
| `POST /api/terminal-sessions/{id}/confirm` | Recording an approval |
| `POST /api/terminal-sessions/{id}/cancel` | Ending an attempt |
| `POST /api/orders/{id}/late-approval` | Reporting a late approval |
| `POST /api/orders/{id}/pay` | Simulated payment |

### Sync

| Call | Used for |
|---|---|
| `GET /api/sync/device-config` | Settings needed to sell offline |
| `POST /api/sync/pull` | Combined pull |
| `GET /api/sync/{table}` | Per-table pull, when the combined pull is not used |
| `GET /api/sync/removals` | Deleted rows |
| `POST /api/sync/orders` | Sending a local order |
| `POST /api/sync/orders/{id}/payments` | Sending a payment only |
| `POST /api/sync/status` | Device sync status |

### Pages, files and logs

| Call | Used for |
|---|---|
| `GET /api/landing/{pageKey}` | Landing page address and content hash. The kiosk uses `KIOSK_LANDING` |
| `GET /resource/...` | Landing page and its files |
| `GET /api/resources/{id}` | Product images and payment method icons |
| `POST /api/resources` | Log upload, from native code |

The app also shows the link `/api/invoices/{id}` as the invoice QR.

---

## Behaviour to know

- **Timeouts and retry.** Most calls made through `ApiClient` wait 8 s and try once more when there is no answer. **This includes order and payment POST calls,** so the server must handle a repeat safely. Sync and file downloads have their own rules.
- **Order ids** are UUIDv7, made on the device. Sending the same order again must not create a second one.
- **Store id.** With a signed-in session that has a store, quote and order calls leave `storeId` out and the server uses the session. Barcode lookups send it.
- **Errors.** The app reads the `message` field of an error answer. It handles 401 (rejected sign-in), 404 and 409 as their own cases, and a refused coupon as a 422.
- **API level.** The app reads `api_level` to decide on the combined pull, which needs level 7. See the backend's `docs/api-levels.md`.

---

## Contracts in the backend repo

| Backend document | Subject |
|---|---|
| `docs/offline.md` | Offline mode and sync |
| `docs/sync-combined-pull.md` | Combined pull |
| `docs/api-levels.md` | `api_level` |
| `docs/roles-permissions.md` | Auth domains and device management |
| `docs/payment-methods.md` | Payment methods |
| `docs/landing-pages.md`, `docs/resource-management.md` | Landing pages and files |

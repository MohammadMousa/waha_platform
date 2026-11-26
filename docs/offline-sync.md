# Offline mode and sync

How the kiosk keeps working without the server, and how it exchanges data with it. The server contract is in the backend repo: `docs/offline.md` and `docs/sync-combined-pull.md`.

The code is in `lib/data/`: `catalog/`, `orders/`, `sync/`, `resources/` and `db/`.

**Principle:** offline operation keeps sales going through a fault. It is a fallback, and the kiosk keeps trying to reach the server.

---

## Offline levels

The server property `offline_mode` sets the level. The kiosk saves it, so it also applies after a restart without a server. If a config request fails, the last level stays.

| Level | Catalog reads | New orders | Scheduled pull |
|---|---|---|---|
| `off` (default, also any unknown value) | Server | Server | No |
| `caching` | Server first. The saved copy only when the server cannot be reached | Server first. On the device when it cannot be reached | No |
| `full` | Local database | On the device | Yes |

The old values `true` and `false` mean `full` and `off`.

**"Cannot be reached"** means no connection, a timeout or a 5xx answer. A 4xx answer is the server's real answer and is never replaced by local data.

**A new `full` device** behaves like `caching` until `products`, `barcodes` and `payment-methods` have each been pulled once and the device settings are saved. Selling does not wait for the first download.

---

## What works differently offline

- **Coupons** are always checked by the server. A cart with a coupon never falls back to local pricing.
- **Offers** exist only on the server. A local price has no offer discount.
- **Local pricing** is each line's net price plus its own tax.
- **Search** covers English and Arabic names. Tags are not synced, so it does not search them.
- **Payment methods** offline: active, allowed for `KIOSK`, enabled for the store and marked offline capable. `PAYMENT_URL` also needs a URL. See [payments.md](payments.md).
- **Product missing from the local copy** (`full`): the kiosk asks the server once, waits 3 s at most, and saves a complete answer.
- **Inactive products** are refused unless the property `scan_disabled_products` is on.

In `caching`, good server answers are saved as they happen. Only a complete product answer creates or replaces a product, and an older answer never replaces a newer one.

---

## Local orders

An order made on the device gets a UUIDv7 id and a reference `<prefix>-<device number>-<4-digit serial>`. The prefix is the store's short code, or else the store id. The serial counts up per device and goes back to 0 after 9999. After a reinstall it continues from the last serial the server saw.

This needs the saved device settings. A device that never received them cannot make local orders.

The invoice link of a local order ends in `?offline=1`, so the server can show a waiting page until it has the order.

### States

| State | Meaning |
|---|---|
| `LOCAL` | Not paid. Stays on the device |
| `PENDING` | Paid, waiting to be sent |
| `PAY_PENDING` | The server has the order. Only the payment is waiting |
| `SYNCED` | The server has everything |
| `DEAD` | The server refused it for good. Waits for a person |

### Sending

- A paid order is sent right away, and a timer tries again every 3 minutes. Customer activity does not pause sending.
- On a network error, 408, 429 or 5xx, the pass stops and the order is retried later. The delay doubles each time, up to 15 minutes, with some random spread. A longer `Retry-After` from the server wins.
- Another 4xx moves the order to `DEAD`, unless the answer says it can be retried. Settings has a retry button for these.
- A 401 or 403 stops sending and keeps every order. Settings shows a warning.
- Before a QR link payment, an unpaid local order is sent at once, because the server must know it.

---

## Pull

The pull runs on a schedule in `full` only. **Pull now** in Settings and the `cmd=sync-pull` scan command run one by hand, see [device-operations.md](device-operations.md). In `caching`, a scheduled cycle only refreshes the device settings.

**Tables, in order:** `products`, `barcodes`, `categories`, `payment-methods`, `store-payment-methods`, `product-images`. Deleted rows ("removals") are applied first.

### When

| Case | Delay |
|---|---|
| After app start | Start delay (60 s), plus a fixed slot for this device inside the stagger window (180 s), plus up to 5 s |
| Normal | Every interval (60 minutes unless the server says otherwise), plus up to 10% |
| Server reachable again | Random, up to 60 s |
| Server asks to wait | Its `Retry-After`, up to 1 hour |
| First download stopped by a customer | 60 s |
| Level changed to `full` | Random, up to 60 s |

A scheduled pull waits for the screen to be idle (10 s) and stops when a customer touches or scans. A manual pull does not.

### Combined or per table

The kiosk uses one combined request, `POST /api/sync/pull`, when the server reports `api_level` 7 or higher and the property `sync_combined_pull` is not `false`. If the server answers 404, it uses one request per table until the app restarts.

With the combined pull, the server can switch a table off or give it a freshness period. A scheduled pull leaves those tables out. A manual pull asks again for tables that are still fresh, but not for switched-off ones.

### Safety rules

- A page and its position are saved in one transaction. A lost request saves nothing.
- A new run starts 10 s before the saved position. Rows are updated in place, so repeats do no harm. The row count shown counts only new or changed rows.
- Removals go in before table data. If the server asks for a reset, every table is pulled again from the start.
- A request that gets no answer is tried again on a new connection: 3 tries by default, with a 5 s connect limit. A real server answer is not retried this way.

---

## Server properties

| Property | Default |
|---|---|
| `offline_mode` | `off` |
| `scan_disabled_products` | off |
| `sync_pull_start_delay_seconds` | 60 |
| `sync_pull_interval_minutes` | 60 |
| `sync_pull_patch_size` | 200 |
| `sync_pull_timeout_seconds` | 30 |
| `sync_connect_timeout_seconds` | 5 (2 to 30) |
| `sync_connect_retries` | 3 tries (1 to 5) |
| `sync_stagger_seconds` | 180 (30 to 3600). The start slot is set at app start |
| `sync_idle_seconds` | 10 |
| `sync_combined_pull` | on |
| `sync_push_interval_minutes` | 3 |
| `sync_push_timeout_seconds` | 60 |
| `sync_push_retry_max_delay_minutes` | 15 |
| `offline_unpaid_cleanup_enabled` | off |
| `offline_audit_cleanup` | off |
| `offline_unpaid_cleanup_days_offset` | 15 (1 to 365) |
| `resource_cache_max_mb` | 200 |
| `resource_cache_max_age_days` | 30 |
| `resource_cache_recheck_minutes` | 10 |

### Cleanup of old local orders

Two separate rules, both off by default. One removes old orders that were never paid. The other removes old orders the server already has. **Paid orders that are not sent yet, and `DEAD` orders, are never removed,** because the device may hold the only copy.

---

## Images and landing page files

One cache serves every offline level. Nothing is downloaded in advance: a file is saved the first time a screen shows it.

- `/api/resources/<id>` never changes, so it is never checked again.
- `/resource/...` paths are checked for a new version. The old file stays on screen until the new one has fully arrived.
- Logs and failed answers are never cached.
- Cleanup removes files not shown for the maximum age, then the least recently shown ones over the size limit. It keeps the landing page and its files, and removes nothing while the server cannot be reached.

See [landing-page-rendering.md](landing-page-rendering.md).

---

## Local database

SQLite through Drift, database name `waha_kiosk`, schema version 7. It holds the catalog tables, pull positions, device settings, local orders with their lines and payments, the reference counter and the cached file list.

**To change the schema:** raise `schemaVersion` and add a new migration step in `lib/data/db/app_database.dart`. Never edit an old step, because devices in use run them in order.

---

## Checking sync on a device

- Settings shows row counts, the last pull for each table, the last result, waiting orders and refused orders.
- At the `Warn` log level, a pull writes its summary line only when it brought rows, failed, or was the first success since app start. Quiet does not mean it stopped.
- The kiosk reports its last pull, last send and waiting order counts to the server (`POST /api/sync/status`).

# Payments

How the kiosk takes a payment, and what it does when something goes wrong.

Main files: `lib/screens/invoice_screen.dart`, `lib/services/geidea_terminal_bridge.dart`, `lib/services/late_approval_service.dart`, `lib/screens/qr_payment_screen.dart`, and in `android/app/src/main/kotlin/com/waha/kiosk/`: `MainActivity.kt` and `PaymentCallbackClassifier.kt`.

---

## One rule first

**When the terminal has approved a payment, the customer has paid.** If recording it fails, that is a reconciliation problem for us. The kiosk must never turn an approval into a decline, and a backend problem does not stop sales. This is a product rule, also written in the code. Change it only on an explicit request.

---

## Payment methods

The invoice screen asks the server for the methods of the store (`mode=KIOSK`). The `provider` value of a method decides the flow.

| Provider | What the kiosk does |
|---|---|
| `TERMINAL` | Card payment on the Geidea terminal over USB |
| `QR_LINK` | Asks the server for a payment link, shows its QR and waits |
| `PAYMENT_URL` | Shows a QR of `<paymentUrl>/invoice/<orderId>` and waits |
| `SIMULATED` | Pays at once through the server, for testing |

Any other provider is logged as not supported.

**Automatic choice.** When the invoice first loads, the kiosk selects the only method after 4 s. With several methods it picks one after 5 s: `TERMINAL` if the store has it, else the first one. This happens only on that first load. After a decline or a cancel the customer must choose.

While a payment dialog is open, the idle guard and the scheduled restart are held back.

---

## Card terminal

### Steps

1. **Busy check.** If the terminal answered "busy" in the last 10 s, the kiosk refuses a new payment.
2. **USB service check.** The kiosk makes sure the SDK's USB service is still there and re-opens it if the SDK destroyed it. If that fails, the payment does not start.
3. **Hold.** If an earlier attempt has no final answer, the new one waits for the rest of the terminal timeout. See [The hold](#the-hold).
4. **Optional reset.** With Settings → "Reset Terminal before Payment" on (default off), the USB connection is closed and opened again.
5. **Session.** The kiosk creates a terminal session for the order (`POST /api/orders/{id}/terminal-session`, or a local one for an order made on the device).
6. **Purchase.** The amount and a reference go to the SDK. The wait starts.
7. **Result.** Approved: the session is confirmed and the paid screen opens. Anything else: the session is cancelled and the dialog shows why.

### Reference sent to the terminal

The SDK takes at most 16 letters and digits. The kiosk sends the order id without hyphens, cut to 16 characters. Order ids are UUIDv7, so this value can be searched as the start of an order id. The order id itself does not change.

### Reading the SDK's callbacks

The SDK calls back several times for one payment. `PaymentCallbackClassifier` decides what each call means.

| Callback | Meaning |
|---|---|
| Status `1`, no receipt | Progress: the acknowledgement or a step code. Not a result |
| Status `1`, no receipt, code `07` | Terminal busy. Final: declined |
| Status `1` with a receipt | Final result. Approved when `TransactionStatusCode` is 1. If that field is missing, an approval code counts as approved |
| Status `0` | SDK or terminal error. Final: declined, with the error code in the message |

The native side answers the app once, on the first final callback. An approval code is not needed for an approval. If it is missing, the kiosk sends the RRN, or `APPROVED-NO-CODE`.

### Cancel

- Cancel is shown only until the terminal acknowledges the command. After that the terminal owns the attempt.
- Cancel ends the app's wait, cancels the session and closes the dialog.
- **Cancel cannot stop a purchase the terminal already has.** The SDK has no documented call for that. An approval can still follow. See [Late approval](#late-approval).

### Timeout: "result unknown"

If no final answer arrives in time, the dialog says the result is unknown, not that the payment failed, because the card may still be charged. The kiosk cancels the session and writes diagnostics to the log. The order keeps its server status.

| Setting | Detail |
|---|---|
| Default | 60 s |
| Per device | Settings, 10 to 80 s |
| For the organization | Server property `terminal_timeout_seconds`, kept between 10 and 80 s. When set, it replaces the device value |

The upper limit exists because the server's terminal session expires after 90 s.

A failed or unknown dialog closes by itself after 20 s. The "approved but not recorded" message stays until someone closes it.

### The hold

When a purchase is sent, the kiosk saves a pending record on disk. A final answer removes it, also when that answer comes late. A timeout or a cancel leaves it in place.

While the record exists, a new payment waits until the terminal timeout has passed since the earlier attempt **started**. This prevents two purchases on the terminal at once. The customer sees a countdown.

The wait uses the time since boot, so changing the tablet clock does not affect it. It is skipped after a tablet restart, if the record cannot be read, or if the SDK's USB service had been lost and was re-opened.

---

## When an approval cannot be recorded

What happens when the card is approved but the confirmation to the server fails:

| Situation | Result |
|---|---|
| Order made on the device (offline) | The payment is saved on the device first, then sent. See [offline-sync.md](offline-sync.md) |
| `caching` mode, server order, no connection or a 5xx answer | The payment is kept on the device and sent later. The order shows as paid |
| Any other case, including a 4xx answer | The dialog shows "approved but not recorded" for staff. Reconcile it by hand |

---

## Late approval

An approval that arrives after the app stopped waiting (timeout or cancel).

1. The bridge sees an approval for an attempt that was already ended.
2. `LateApprovalService` saves it on disk, so a restart does not lose it.
3. For an order held on the device, it marks the order paid there and sends it later.
4. For other orders it calls `POST /api/orders/{id}/late-approval`.

**The server pays the order only when** it is still `CREATED`, the amount matches, and it is younger than `late_approval_expiration_minutes` (default 3, counted from order creation). A repeated report with the same RRN answers `PAID`.

| Answer | What the kiosk does |
|---|---|
| `PAID` | Done |
| `IGNORED` or rejected (4xx other than 401) | Stops and logs "reconcile by hand" |
| No connection or server error | Tries again every 10 s, at most 40 tries, then logs "reconcile by hand" |

A try without a signed-in device also counts toward the 40.

**The card was charged in every one of these cases,** also when the order stays unpaid.

---

## QR payments

**`QR_LINK`.** An order made on the device is sent to the server first. If that fails, the kiosk says why and starts nothing. The server returns the QR and its expiry time. The kiosk checks the order every 3 s and also listens on `GET /api/orders/{id}/payment-events` for a faster answer. The regular check works even if that connection drops. An expired QR closes after 20 s.

**`PAYMENT_URL`.** The kiosk checks the order every 3 s for about 5 minutes, then closes the dialog. If `paymentUrl` is empty, it shows that Mobile Payment is not configured. This flow does not send a device-made order to the server first.

**Resumed wait.** An order that is already `PENDING` when the invoice opens is checked every 2 s for about 5 minutes.

---

## Paid screen

All successful flows end here. It shows the invoice QR and goes back to the landing page after the "after invoice" time set in Settings. This countdown runs even when idle timers are off.

---

## Looking into a payment problem

1. Upload the device log (`cmd=upload-logs`).
2. Search for `payment run start` to find each attempt.
3. Search for `PAYMENT VERDICT`, `PAYMENT LATE APPROVAL`, `LATE APPROVAL` and `approved but confirm-to-backend failed`.
4. For "result unknown", compare the time, amount and reference with the terminal or Geidea records before charging again.

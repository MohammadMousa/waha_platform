# Device operations

Logs, admin QR commands, restarts and troubleshooting for a kiosk in use.

---

## Admin commands (QR)

A QR or barcode that starts with `cmd=` is an admin command. It works with the hardware scanner, the camera and the simulator.

| Code | Action |
|---|---|
| `cmd=upload-logs` | Uploads the log and shows the result |
| `cmd=sync-pull` | Pulls updates now and shows progress |
| `cmd=build-info` | Shows version, build, store, host and offline mode. Closes after 1 minute |
| `cmd=profile` | Opens the profile sheet to sign out or change the account |

While an order is placed and unpaid, commands and product scans are blocked. Unknown commands do nothing.

**For developers:** every scan goes through `ScannerManager.handle`. Add scan rules only there.

---

## Logging

### Switches

- **On or off:** the Settings switch or the server property `enable_logging`. Either one turns it on. When off, nothing is written or uploaded.
- **Level:** the server property `Log_Level`: `Info`, `Warn` (default) or `Error`.

`Info` keeps SDK detail, including the SDK log file and captured SDK lines in uploads. `Warn` and `Error` drop most of it and keep USB drops, results, timeouts, late approvals, errors and restarts. Use `Info` only while looking into a problem.

### Log file

The file is `waha_trace.log`. Above 3 MB it is cut to the newest 1.5 MB. It is cleared after a successful upload. SDK log files older than 3 days are deleted at app start, but the 2 newest of each kind are kept.

---

## Uploading logs

**By hand:** `cmd=upload-logs`, the Settings upload button, or the native log viewer, which also works when Flutter cannot start. It needs logging on, a server address and a signed-in device. The result shows a log ID. Admins use this ID to find the log.

A report holds a performance snapshot, log file health, the last 1 MB of the trace, SDK logs at `Info`, and the USB device list.

**Automatic:** triggered by USB disconnects or port failures, a payment with no SDK callback, a contained SDK crash and other trouble signs.

| Property | Default | Meaning |
|---|---|---|
| `auto_log_upload_enabled` | off | Read again before each upload |
| `max_log_uploads_per_hour` | 3 | Limit for automatic uploads. Manual ones are not counted |
| `log_harvest_seconds` | 30 (10 to 240) | Quiet time that collects related events into one upload |

One incident is held open for 5 minutes at most. A new `log_harvest_seconds` value applies from the next incident but one.

---

## Restarts and recovery

### Scheduled restart

It gives the app, the SDK and the USB connection a clean start.

| Property | Default |
|---|---|
| `device_auto_restart_enabled` | off |
| `device_auto_restart_hours` | 2 (0.25 to 168) |
| `device_auto_restart_wait_minutes` | 3 (1 to 60) |

It runs only on the landing page with an empty cart, no order, no payment and no pending terminal attempt. A 10 s countdown lets the user postpone it. If the kiosk is busy, it asks again after the wait time. It never runs in the first 10 minutes. The time is app uptime, so the tablet clock does not matter. A line starting `PERF at restart` is logged first when logging is on.

In Android exit records, a deliberate restart can look like a killed process. Check for `STARTED AFTER A DELIBERATE RESTART` in the log.

### SDK recovery

- **Lost USB service:** the SDK can destroy its service after the app has been in the background. The app re-opens it, and checks it before every payment.
- **SDK crash:** a runtime error in an SDK background thread is contained, logged, and followed by a reconnect and a log upload. At most 3 per minute. Other crashes end the app as normal.

---

## Heartbeat and performance

**Heartbeat:** with `heartbeat_minutes` above 0 (up to 1440), a signed-in kiosk calls `POST /api/kiosk/heartbeat`. An outage is logged once, and again when it ends.

**Performance counters:** screen frames, local database timing, sync results and sounds. They run only while logging is on.

---

## Other server properties

`terminal_timeout_seconds` is described in [payments.md](payments.md). Offline, sync, cleanup and cache properties are in [offline-sync.md](offline-sync.md#server-properties).

---

## Diagnostic tools

Developer Tools include the log viewer, USB device list, terminal status check, full terminal diagnostic, SDK state, serial channel probe, previous exit reasons, session info and a restart test.

The full diagnostic takes about 30 s. The diagnostic and the probe disrupt the terminal connection, so do not run them during a payment.

---

## Troubleshooting

| Problem | What to check |
|---|---|
| Terminal not found or no answer | Cable, power and the terminal screen. Then run the terminal status check |
| "Result unknown" | Check the terminal or Geidea records before charging again. See [payments.md](payments.md#looking-into-a-payment-problem) |
| No acknowledgement, repeatedly | Set `Log_Level=Info`, reproduce it, upload the log |
| Upload fails | Logging on, server address, device signed in |
| No automatic uploads | `enable_logging`, `auto_log_upload_enabled`, the hourly limit |
| Products out of date | `cmd=sync-pull`, then see [offline-sync.md](offline-sync.md#checking-sync-on-a-device) |

**Comparing logs:** trace lines carry epoch milliseconds. Report headers use the tablet's time zone, which can differ between kiosks, so compare in UTC. Check the `device=` header before comparing versions.

---

## Log size at `Warn`

- The payment timeline includes captured SDK lines, such as `LAST BYTE`, inside one larger entry that the line filter does not remove (`TerminalDiagnostics.timeline`).
- USB device lists requested with a reason through `UsbDiagnosticsChannel` are written in full each time.

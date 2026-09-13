# Landing Page Rendering (Kiosk)

How the kiosk app loads and displays the dynamic HTML landing pages described in `waha/docs/landing-pages.md` and `waha/docs/resource-management.md` — this doc covers only the kiosk-side rendering pipeline, not the URL scheme or data model.

---

## Pipeline

```
LandingScreen.initState()
  └── LandingCache.readHtml(pageKey)        — local file, shown instantly if present
  └── (background) ApiClient.getLandingPage — GET /api/landing/{pageKey}
        └── contentHash unchanged → keep cached HTML, do nothing
        └── contentHash changed   → fetch bytes, LandingCache.writeHtml, reload WebView
```

The HTML is always cached on disk with its **original, root-relative** paths (e.g. `src="/resource/waha_corp/waha/res/x.jpg"`) — never with a server host baked in. That's what makes the cache portable across server IP changes; the host is only ever added back in at display time.

---

## Turning a relative path into something the WebView can load

`WebViewController.loadHtmlString()` does not give the loaded document a real origin the way a normal browser navigation does — so a raw root-relative `<img src="/resource/...">` has nothing to resolve against on its own. Two different mechanisms fix this, and **both matter**, because they don't run on the same platforms:

- **Android / iOS**: `loadHtmlString(html, baseUrl: AppConfig.apiBaseUrl)` — the platform WebView (native `loadDataWithBaseUrl` under Android) resolves relative references against `baseUrl` itself, the same way a real page load would. This is the primary, most robust mechanism.
- **Flutter Web**: the `baseUrl` parameter is silently ignored (`webview_flutter_web` loads the document via a `data:` URI with no base at all). `LandingCache.resolveAbsolutePaths()` is the only thing that makes images work there — it rewrites `src=`/`href=`/`url()` values by hand before the HTML is handed to `loadHtmlString`.

Both paths are kept in the code (`landing_screen.dart`, `landing_cache.dart`) — don't remove the regex rewriting on the assumption `baseUrl` covers everything; it doesn't, on web.

---

## Two independent network stacks — the thing that actually matters when debugging this

The page's own HTML/metadata (`ApiClient`, `/api/landing/...`) is fetched over **Flutter's own `dart:io`-based HTTP client**. The images *inside* that HTML are fetched by **the platform's native WebView engine** (Android System WebView / Chromium, or WKWebView) — a completely separate network stack with its own DNS cache, connection pool, and OS-level network policy.

This split is easy to miss and produces a very specific, confusing symptom: **the page loads, background update checks succeed, hashes match — and images are still broken.** When that happens, the bug is almost never in this app's Dart code (if the JSON/API layer works, the HTTP client and the URL/data are provably fine) — it's in something that only affects the *native WebView's* traffic specifically:

- Android's per-app Network Security Config blocking cleartext HTTP for the WebView while `dart:io` sockets sail through unaffected (`dart:io` is not subject to Android's `NetworkSecurityPolicy` at all). See `android/app/src/main/res/xml/network_security_config.xml` — a bundled native SDK dependency in this app ships its own network security config with no `<base-config>`, which silently defaults everything *not* explicitly listed to cleartext-blocked, overriding `android:usesCleartextTraffic="true"` in our own manifest. Our own config is declared explicitly (with `tools:replace`) specifically to win that merge.
- Stale DNS/connection state held by the WebView engine after a LAN IP change, if the backend host isn't a stable IP.

### How to actually see what the WebView is doing

`chrome://inspect` can't be reached through most browser automation and doesn't always show the right target automatically. The reliable path, with a device connected via `adb`:

```bash
adb shell cat /proc/net/unix | grep webview_devtools_remote   # find the debug socket for the running app's PID
adb forward tcp:9333 localabstract:webview_devtools_remote_<pid>
curl -s http://localhost:9333/json                             # lists the WebView's own DevTools target(s)
```

A plain WebSocket client hitting that target's `webSocketDebuggerUrl` gets rejected by Chrome's origin allowlist (`403 ERR_CLEARTEXT`-style checks don't apply here, but WS handshake origin checks do) unless the connection is made with `suppress_origin=True` (Python `websocket-client`) — a real browser's `chrome://inspect` UI handles this internally, a bare script has to work around it explicitly. Once connected, `Network.enable` + `Page.reload` and reading `Network.loadingFailed` events gives the *actual* Chromium-level error (e.g. `net::ERR_CLEARTEXT_NOT_PERMITTED`) for each image request — far more direct than guessing from Dart-side symptoms.

---

## Debug toast / dev tools

`LandingScreen`'s `_log()` calls are gated by `LocalPrefs.devToolsUnlocked` (tap the version number 10× in Settings — a local-only unlock, no login required) and show up as on-screen toasts: fetch attempts, hash comparisons, cache hits/misses. The **Server Connection** panel lives under this same dev-tools gate (not behind `MANAGE_STORES`) specifically so a device with a wrong/changed LAN IP can still have it fixed without needing to log in first — logging in itself requires reaching the (possibly misconfigured) server.

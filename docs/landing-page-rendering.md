# Landing page rendering

How the kiosk loads and shows the HTML landing page. The URL scheme and data model are described in the backend repo: `docs/landing-pages.md` and `docs/resource-management.md`.

Main files: `lib/screens/landing_screen.dart`, `lib/services/landing_cache.dart`, `lib/data/resources/html_assets.dart`.

---

## Loading and updating

The kiosk uses one page, `KIOSK_LANDING`.

1. The saved page is shown at once, if there is one. With no page, a built-in scan screen shows.
2. With a token and a store ready, the app asks `GET /api/landing/KIOSK_LANDING`.
3. The page is downloaded only when its content hash changed. The old copy shows until the new one has fully arrived.

**When it checks:** when a token and store become ready, when either changes, 30 s after the first of these, and then every `check_landing_page_interval_minutes` (default 30, 1 to 1440).

A failed check keeps the saved page. A 404 also leaves the current `KIOSK_LANDING` page on screen.

---

## Files and addresses

The page is saved by the resource cache with its **original root-relative addresses**, without a server host, so it still works after the server address changes. See [offline-sync.md](offline-sync.md#images-and-landing-page-files).

At display time, in memory only:

1. `LandingCache.resolveAbsolutePaths` makes `src`, `href`, `action` and `url()` values absolute.
2. `HtmlAssets.withSavedCopies` replaces `src` and `url()` addresses that are already saved with the data itself. This works without a server. Files over 3 MB stay as server addresses. A file not saved yet loads from the server and is saved for next time.
3. The page is loaded with `loadHtmlString`, with the server address as the base.

Both the base address and the rewriting are needed. Flutter web ignores the base address, so do not remove the rewriting.

---

## What a page can do

### Layout

Add `<meta name="waha-mode" content="fullscreen">` to fill the screen without the app bar and bottom bar.

Without it, the app bar title can come from the page: `title{ar=..., en=...}` within the first 1500 characters. Otherwise it is the store name, then the app name.

### Language

After loading, the app sets `lang` and `dir` on the page. If the page has a button with id `langBtn` and a global `translations` object, it also fills every `data-i18n` element.

### Links

The app blocks page navigation and handles links with the path `/screen`:

| `name` | Opens | `tag` |
|---|---|---|
| `browse_screen` | Browse | Optional. Used as the search text and the title |
| `categories_screen` | Categories | Not used |
| `search_screen` | Search | Passed as a query argument. The route does not currently read it |
| `cart_screen` | Cart | Not used |

```html
<a href="/screen?name=browse_screen&tag=Desserts">Desserts</a>
```

JavaScript runs in the page on Android.

When an item is added to the cart while the landing page is open, the cart opens.

---

## Debugging

### Page loads but images are broken

The app and the page use **two separate network stacks**. The page's data is fetched by the app's own HTTP client. Images that are not saved yet are fetched by the Android WebView, which has its own DNS cache, connections and network policy.

So updates can succeed while images fail. Check:

- **WebView network settings.** The WebView follows the Android network security settings. The app's own HTTP client does not. See the comments in `res/xml/network_security_config.xml`.
- **Old connection state** in the WebView after a server address change.

### Developer messages

With Developer Tools unlocked, the landing page shows short messages about fetches, hashes and cache use.

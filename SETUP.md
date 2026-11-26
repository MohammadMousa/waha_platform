# Waha Kiosk — setup

## Prerequisites

- Flutter SDK (stable) with the Android toolchain
- An Android device or emulator; a Geidea terminal on USB for real card payments
- A reachable Waha backend, and a **device account** (username + PIN) for each kiosk

## One-time setup

```bash
flutter pub get
flutter gen-l10n        # only if lib/l10n/generated/ is ever missing
```

`l10n.yaml` (project root) and `generate: true` in `pubspec.yaml` produce the localisation code from `lib/l10n/app_en.arb` and `app_ar.arb`.

After changing the database tables, regenerate the Drift code with `dart run build_runner build`, and add a migration step. See [docs/offline-sync.md](docs/offline-sync.md#local-database).

## Running against the backend

```bash
# Android emulator (talks to the host machine through the special alias)
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8081

# Real device on the same LAN as the backend
flutter run --dart-define=API_BASE_URL=http://<backend-lan-ip>:8081

# From a settings file
flutter run --dart-define-from-file=config/dev.json
```

Without `API_BASE_URL` the app falls back to the emulator address, which a real device cannot reach.

### Build settings

| Setting | Effect |
|---|---|
| `API_BASE_URL` | The app's default server |
| `ENABLE_SIMULATOR` | Simulator tools. Off by default. **The dev example file turns it on. Never use it in a release** |
| `LOGGING=true` | Turns logging on |
| `GEIDEA_MOCK=true` | Approves card payments without a terminal. **Testing only** |

## Release builds

```bash
cp config/prod.example.json config/prod.json   # fill in the real server address
scripts/build_release.sh prod                  # bumps the version, then builds the APK
```

Use the script, not a raw `flutter build`, so the version bump takes effect. The app id is `com.waha.kiosk`. It installs beside any older app with another id, and does not take over its sign-in or settings. `config/*.json` is git-ignored except the `*.example.json` templates.

## First launch on a device

1. Install the APK.
2. On the **Device Login** screen, enter the device username and PIN.
3. The store comes from the device account, and the landing page opens.
4. Connect the Geidea terminal over USB, then check it: Settings → POS Terminal Options.
5. To sign out or change the account: scan `cmd=profile`, then enter the PIN.

If the server address is wrong, change it under Server Connection → Custom Connection.

See [docs/architecture.md](docs/architecture.md) for sign-in and connection rules.

## What is saved

The store, language, timers, device token and settings survive a restart. The local database holds the catalog and local orders. The device PIN is never saved. **Uninstalling the app or clearing its data can lose paid orders that are not sent yet.** Check Settings for waiting orders first.

## Checks before committing

```bash
flutter analyze
flutter test
```

## Not built here

- A provisioning wizard for new devices (the account is created in the dashboard)
- The web and phone shopping flows and the admin screens, which are in `waha_client` and `waha_admin`

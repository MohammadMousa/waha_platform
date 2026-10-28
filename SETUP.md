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

## Running against the backend

```bash
# Android emulator (talks to the host machine through the special alias)
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080

# Real device on the same LAN as the backend
flutter run --dart-define=API_BASE_URL=http://<backend-lan-ip>:8080

# From a settings file
flutter run --dart-define-from-file=config/dev.json
```

Without `API_BASE_URL` the app falls back to the emulator address, which a real device cannot reach.

To keep the simulator out of a build entirely (it is off by default):

```bash
flutter build apk --dart-define=ENABLE_SIMULATOR=false
```

## Release builds

```bash
cp config/prod.example.json config/prod.json   # fill in the real server address
scripts/build_release.sh prod                  # bumps the version, then builds the APK
```

Use the script, not a raw `flutter build`, so the version bump takes effect. `config/*.json` is git-ignored except the `*.example.json` templates.

## First launch on a device

1. Install the APK. The app id is `com.waha.kiosk`, so it installs as a new app beside any older one.
2. On the **Device Login** screen enter the device username and PIN.
3. The store comes from the device account, and the landing page loads. No other login or store choice exists.
4. To reach Settings later: 10 taps on the cart screen, then the device PIN. To sign out or change the account: scan a QR containing `cmd=profile`, then enter the PIN.

If the server address is wrong, Settings → Developer Tools (10 taps on the version label) → Server Connection → Custom Connection sets another server.

## Persistence

Store id, locale, kiosk timers, the device token and the settings survive an app restart or device reboot (`shared_preferences`). The device PIN is never stored: after a restart the app restores the session from its saved token, and a rejected token leaves the device on the Device Login screen.

## Checks before committing

```bash
flutter analyze
flutter test
```

## Not built here

- Offline operation (a local order queue with sync on reconnect)
- A provisioning wizard for new devices (the account is created in the dashboard)
- The web / phone shopping flows and the admin screens — those live in `waha_client` and `waha_admin`

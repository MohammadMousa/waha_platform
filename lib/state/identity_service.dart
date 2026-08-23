import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../services/local_prefs.dart';
import 'browsing_mode_service.dart';

const _uuid = Uuid();

/// Resolves the `username` field FRONTEND_CONTEXT.md now requires on
/// every `POST /api/orders` — mandatory for ZATCA compliance per the
/// doc, deliberately a plain string with no separate "type" field.
///
/// This is NOT a real identity system — accounts/login are still
/// explicitly out of scope (FRONTEND_CONTEXT.md's own "not built yet"
/// list, unchanged by this update). Two distinct sources, matching the
/// doc's own examples and the identity distinction settled on earlier
/// (see BACKEND_CONTEXT.md item 4):
///
/// - Kiosk: "a fixed kiosk-account identifier" — a configurable,
///   persisted per-device value (Settings), since Kiosk's identity
///   doesn't change per customer.
/// - Shopping / Normal (no real login exists yet, in either): "a phone
///   number / auto-generated UUID for a webapp guest checkout" — a
///   generated guest id. Deliberately regenerated every app launch
///   rather than persisted: it's supposed to be a lightweight guest
///   identity, not a quietly-persistent tracking id masquerading as one.
class IdentityService extends ChangeNotifier {
  String kioskUsername;
  final String guestUsername;

  IdentityService({required this.kioskUsername, required this.guestUsername});

  void setKioskUsername(String value, {bool persist = true}) {
    kioskUsername = value;
    if (persist) {
      LocalPrefs.setKioskUsername(value);
    }
    notifyListeners();
  }

  /// The value to actually send as `username` on checkout, given the
  /// currently active browsing mode. Read at checkout time, not cached —
  /// see order_flow_controller.dart.
  String get activeUsername =>
      browsingModeService.mode == BrowsingMode.kiosk ? kioskUsername : guestUsername;
}

/// Obviously-a-placeholder on purpose — if this shows up in a backend
/// log or dashboard un-configured, it should be immediately recognizable
/// as "nobody set this yet," not a plausible-looking fake identifier.
final identityService = IdentityService(
  kioskUsername: 'kiosk-CHANGE-ME',
  guestUsername: 'guest-${_uuid.v4()}',
);

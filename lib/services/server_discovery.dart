import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:network_info_plus/network_info_plus.dart';

/// Auto-detects the backend server on the local network by parallel-probing
/// common last-octet candidates on the same subnet as the device's WiFi IP.
/// Only runs on Android; only runs on first launch (no stored URL).
///
/// Result is bridged to the UI via [justDiscoveredUrl]:
///   null  → discovery did not run this launch
///   ''    → ran but found nothing
///   URL   → found and already saved to LocalPrefs
class ServerDiscovery {
  ServerDiscovery._();

  // Set by main.dart during _resolveStartupConfig; consumed once by LandingScreen.
  static String? justDiscoveredUrl;

  static const int _port = 8081;
  static const _timeout = Duration(milliseconds: 1500);

  // Most LAN servers sit in low or round-number octets. Probe these first.
  static const _candidates = [
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20, 50, 100, 150, 200, 254,
  ];

  static Future<String?> discover() async {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      final deviceIp = await NetworkInfo().getWifiIP();
      if (deviceIp == null || deviceIp.isEmpty) return null;

      final parts = deviceIp.split('.');
      if (parts.length != 4) return null;
      final subnet = '${parts[0]}.${parts[1]}.${parts[2]}';
      final deviceOctet = int.tryParse(parts[3]) ?? -1;

      // Include neighbours of the device's own octet — the server is often
      // on a nearby address assigned by the same DHCP pool.
      final probeSet = <int>{
        ..._candidates,
        if (deviceOctet > 1) deviceOctet - 1,
        if (deviceOctet < 254) deviceOctet + 1,
      }..remove(deviceOctet);

      return await _race(subnet, probeSet.toList());
    } catch (_) {
      return null;
    }
  }

  // Fires all probes concurrently and returns the first URL that responds.
  static Future<String?> _race(String subnet, List<int> octets) async {
    final completer = Completer<String?>();
    var remaining = octets.length;

    for (final octet in octets) {
      final url = 'http://$subnet.$octet:$_port';
      _ping(url).then((ok) {
        remaining--;
        if (ok && !completer.isCompleted) {
          completer.complete(url);
        } else if (remaining == 0 && !completer.isCompleted) {
          completer.complete(null);
        }
      });
    }

    return completer.future.timeout(
      const Duration(seconds: 4),
      onTimeout: () => null,
    );
  }

  static Future<bool> _ping(String baseUrl) async {
    try {
      final resp = await http
          .get(Uri.parse('$baseUrl/api/config'))
          .timeout(_timeout);
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}

import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/auth_session.dart';
import '../models/cart_item.dart';
import '../models/category.dart';
import '../models/order.dart';
import '../models/pay_result.dart';
import '../models/payment_method.dart';
import '../models/product.dart';
import '../models/product_page.dart';
import '../models/quote.dart';
import '../models/store.dart';
import '../models/terminal_session.dart';
import 'api_exceptions.dart';
import 'app_info.dart';

class ApiClient {
  final http.Client _http;

  /// When set, this client talks to that server instead of the active one —
  /// used only to test and sign in to a candidate server before switching to
  /// it (see ConnectionSwitcher). The shared app client leaves it null.
  final String? _baseUrl;

  ApiClient({http.Client? httpClient, String? baseUrl})
      : _http = httpClient ?? http.Client(),
        _baseUrl = baseUrl;

  Uri _uri(String path) =>
      Uri.parse('${_baseUrl ?? AppConfig.apiBaseUrl}$path');

  /// Reachability check for a candidate server: unauthenticated
  /// GET /api/config, 5s, no retry. Unlike [getConfig] it says *why* it
  /// failed. Returns null on success, otherwise a short human message.
  /// The raw exception text of the last failed [probe], for a "Details" view.
  String? lastProbeRaw;

  Future<String?> probe() async {
    lastProbeRaw = null;
    try {
      final resp = await _http
          .get(_uri('/api/config'))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) {
        return 'Server answered HTTP ${resp.statusCode} — not a Waha server, or wrong base path';
      }
      final body = jsonDecode(resp.body);
      if (body is! Map) {
        return 'Server answered, but not with Waha config — wrong address?';
      }
      return null;
    } on FormatException catch (e) {
      lastProbeRaw = e.toString();
      return 'Server answered, but not with Waha config — wrong address?';
    } catch (e) {
      final t = e.toString();
      lastProbeRaw = t;
      if (t.contains('TimeoutException')) {
        return 'No answer within 5 seconds — check host, port and network';
      }
      if (t.contains('HandshakeException') || t.contains('CERTIFICATE')) {
        return 'Secure connection failed — check HTTPS vs HTTP and the certificate';
      }
      if (t.contains('Connection refused')) {
        return 'Connection refused — nothing is listening on that host/port';
      }
      if (t.contains('Failed host lookup')) {
        return 'Host not found — check the name or IP';
      }
      return 'Cannot reach the server ($t)';
    }
  }

  Map<String, String> _headers({String? token}) => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  /// Every non-2xx body is {"message": "..."}. Pulls that out, falling back
  /// to a generic string if the body doesn't parse.
  String _extractMessage(http.Response resp) {
    try {
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      return body['message'] as String? ??
          'Request failed (${resp.statusCode})';
    } catch (_) {
      return 'Request failed (${resp.statusCode})';
    }
  }

  /// Turns a failed login response into the specific exception: locked
  /// (429/423 or code ACCOUNT_LOCKED), wrong credentials with tries left, or
  /// the plain 401 an older backend sends. Reads snake_case and camelCase.
  ApiException _loginFailure(http.Response resp) {
    final msg = _extractMessage(resp);
    Map<String, dynamic> body = const {};
    try {
      body = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {}
    int? intOf(String a, String b) {
      final v = body[a] ?? body[b];
      return v is num ? v.toInt() : null;
    }

    final code = body['code'];
    if (code == 'ACCOUNT_LOCKED' ||
        code == 'TOO_MANY_REQUESTS' ||
        resp.statusCode == 429 ||
        resp.statusCode == 423) {
      return AccountLockedException(resp.statusCode, msg,
          code: code is String ? code : null,
          retryAfterSeconds: intOf('retry_after_seconds', 'retryAfterSeconds') ??
              int.tryParse(resp.headers['retry-after'] ?? ''));
    }
    if (resp.statusCode == 401) {
      return InvalidCredentialsException(401, msg,
          attemptsRemaining: intOf('attempts_remaining', 'attemptsRemaining'),
          maxAttempts: intOf('max_attempts', 'maxAttempts'));
    }
    return UnknownApiException(resp.statusCode, msg);
  }

  // Bounds every request the same way getConfig() already bounds itself.
  // Without this, a TCP connection that hangs rather than refuses (typical
  // of a real public IP behind a firewall/NAT, unlike a local address that
  // fails instantly) leaves `await request()` unresolved forever — no
  // exception ever fires, so callers' try/catch never triggers. On kiosk
  // startup that means main.dart's `await resolveStartupAuth(...)` (via
  // kioskLogin) never returns, runApp() is never called, and the native
  // splash stays up indefinitely — indistinguishable from a native crash,
  // but reproducible on any device/hardware pointed at an unreachable host.
  //
  // Retries once on any failure (timeout or otherwise) before giving up.
  // Real-world symptom this fixes: the first request in a fresh app
  // session pays for DNS + TCP + TLS setup, which can occasionally cross
  // the 8s bound on real kiosk/phone WiFi even though the backend itself
  // is healthy — the user was manually doing this exact retry by hand
  // (tapping "try again" and it working instantly the second time). One
  // bounded retry here does that automatically, in the one place every
  // endpoint already routes through, instead of patching each call site.
  // Does not retry a successful response with a non-2xx status — those
  // aren't exceptions here, each caller's own statusCode check handles
  // them; this only covers connection/timeout-class failures.
  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request().timeout(const Duration(seconds: 8));
    } catch (_) {
      try {
        return await request().timeout(const Duration(seconds: 8));
      } catch (e) {
        throw NetworkException(e);
      }
    }
  }

  // ---- Auth --------------------------------------------------------

  // POST /api/kiosk/auth/login — device identity, separate auth domain from
  // /api/auth/* (no FK to users; devices/PIN, not username/password). See
  // docs/roles-permissions.md in the backend repo. organizationId defaults
  // to 1 server-side (single-org deployment) if omitted.
  Future<AuthSession> kioskLogin(String username, String pinCode) async {
    final resp = await _send(
      () => _http.post(
        _uri('/api/kiosk/auth/login'),
        headers: _headers(),
        body: jsonEncode({
          'username': username,
          'pinCode': pinCode,
          'appVersion': AppInfo.version,
        }),
      ),
    );
    if (resp.statusCode == 200) {
      return AuthSession.fromJson(jsonDecode(resp.body) as Map<String, dynamic>,
          usernameOverride: username);
    }
    throw _loginFailure(resp);
  }

  // POST /api/kiosk/auth/pin/verify — checks the device PIN for the on-device
  // Settings gate. Bearer device token; no new session; its wrong-attempt
  // counter is separate from the device login lockout. Returns null when the
  // PIN is right, otherwise a short message to show (wrong PIN, cooldown,
  // expired session, network problem).
  Future<String?> verifyKioskPin(String token, String pin) async {
    try {
      final resp = await _http
          .post(_uri('/api/kiosk/auth/pin/verify'),
              headers: _headers(token: token),
              body: jsonEncode({'pinCode': pin}))
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        return body['valid'] == true ? null : 'Incorrect PIN';
      }
      if (resp.statusCode == 429) {
        return loginFailureText(_loginFailure(resp));
      }
      if (resp.statusCode == 400) return 'PIN must be 6 digits';
      if (resp.statusCode == 401) {
        return 'Session expired — restart the app and sign in again';
      }
      return _extractMessage(resp);
    } catch (_) {
      return 'Cannot reach the server to check the PIN';
    }
  }

  // POST /api/kiosk/auth/logout
  Future<void> kioskLogout(String token) async {
    final resp = await _send(
      () => _http.post(_uri('/api/kiosk/auth/logout'),
          headers: _headers(token: token)),
    );
    if (resp.statusCode != 200) {
      throw UnknownApiException(resp.statusCode, _extractMessage(resp));
    }
  }

  // POST /api/auth/logout
  Future<void> logout(String token) async {
    final resp = await _send(
      () =>
          _http.post(_uri('/api/auth/logout'), headers: _headers(token: token)),
    );
    if (resp.statusCode == 200) return;
    final msg = _extractMessage(resp);
    if (resp.statusCode == 401) throw UnauthorizedException(401, msg);
    throw UnknownApiException(resp.statusCode, msg);
  }

  // GET /api/kiosk/auth/me — the Kiosk-mode equivalent of me() above, so a
  // device session can be validated the same way instead of re-logging-in
  // with a locally cached PIN on every start (see AuthService.resolveStartupAuth).
  Future<AuthSession> kioskMe(String token) async {
    final resp = await _send(
      () => _http.get(_uri('/api/kiosk/auth/me'), headers: {
        ..._headers(token: token),
        'X-App-Version': AppInfo.version,
      }),
    );
    if (resp.statusCode == 200) {
      return AuthSession.fromJson(
          jsonDecode(resp.body) as Map<String, dynamic>);
    }
    final msg = _extractMessage(resp);
    if (resp.statusCode == 401) throw UnauthorizedException(401, msg);
    throw UnknownApiException(resp.statusCode, msg);
  }

  // GET /api/config — public, no auth. Returns system_properties as key→value map.
  Future<Map<String, String>> getConfig({int? orgId}) async {
    try {
      final uri = orgId == null
          ? _uri('/api/config')
          : _uri('/api/config').replace(queryParameters: {'orgId': '$orgId'});
      final resp = await _http.get(uri).timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final raw = jsonDecode(resp.body) as Map<String, dynamic>;
        return raw.map((k, v) => MapEntry(k, v.toString()));
      }
    } catch (_) {}
    return {};
  }

  // GET /api/stores
  Future<List<Store>> getStores() async {
    final resp = await _send(() => _http.get(_uri('/api/stores')));
    if (resp.statusCode == 200) {
      final list = jsonDecode(resp.body) as List<dynamic>;
      return list
          .map((e) => Store.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw UnknownApiException(resp.statusCode, _extractMessage(resp));
  }

  // ---- Products ------------------------------------------------------

  // GET /api/products/barcode/{barcode}?storeId={id}
  Future<Product> getProductByBarcode(String barcode, int storeId) async {
    final resp = await _send(
      () => _http.get(_uri(
        '/api/products/barcode/${Uri.encodeComponent(barcode)}',
      ).replace(queryParameters: {'storeId': '$storeId'})),
    );
    if (resp.statusCode == 200) {
      return Product.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
    }
    final msg = _extractMessage(resp);
    if (resp.statusCode == 404) throw ProductNotFoundException(404, msg);
    if (resp.statusCode == 409) throw ProductNotSellableException(409, msg);
    throw UnknownApiException(resp.statusCode, msg);
  }

  // GET /api/products?storeId=&page=&size=&categoryId=&sort=
  Future<ProductPage> getProducts({
    int? storeId,
    int page = 0,
    int size = 50,
    String? token,
    int? categoryId,
    String? sort,
  }) async {
    final resp = await _send(
      () => _http.get(
        _uri('/api/products').replace(queryParameters: {
          if (storeId != null) 'storeId': '$storeId',
          'page': '$page',
          'size': '$size',
          if (categoryId != null) 'categoryId': '$categoryId',
          if (sort != null) 'sort': sort,
        }),
        headers: _headers(token: token),
      ),
    );
    if (resp.statusCode == 200) {
      return ProductPage.fromJson(
          jsonDecode(resp.body) as Map<String, dynamic>);
    }
    throw UnknownApiException(resp.statusCode, _extractMessage(resp));
  }

  // GET /api/products/search?q=&storeId=&page=&size=
  Future<ProductPage> searchProducts({
    required String q,
    int? storeId,
    int page = 0,
    int size = 50,
    String? token,
  }) async {
    final resp = await _send(
      () => _http.get(
        _uri('/api/products/search').replace(queryParameters: {
          'q': q,
          if (storeId != null) 'storeId': '$storeId',
          'page': '$page',
          'size': '$size',
        }),
        headers: _headers(token: token),
      ),
    );
    if (resp.statusCode == 200) {
      return ProductPage.fromJson(
          jsonDecode(resp.body) as Map<String, dynamic>);
    }
    throw UnknownApiException(resp.statusCode, _extractMessage(resp));
  }

  // GET /api/categories?storeId=
  Future<List<Category>> getCategories({required int storeId}) async {
    final resp = await _send(
      () => _http.get(
        _uri('/api/categories')
            .replace(queryParameters: {'storeId': '$storeId'}),
      ),
    );
    if (resp.statusCode == 200) {
      final list = jsonDecode(resp.body) as List<dynamic>;
      return list
          .map((e) => Category.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw UnknownApiException(resp.statusCode, _extractMessage(resp));
  }

  // GET /api/products/{id}
  Future<Product> getProductDetail(int id) async {
    final resp = await _send(() => _http.get(_uri('/api/products/$id')));
    if (resp.statusCode == 200) {
      return Product.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
    }
    final msg = _extractMessage(resp);
    if (resp.statusCode == 404) throw ProductNotFoundException(404, msg);
    throw UnknownApiException(resp.statusCode, msg);
  }

  // ---- Payment methods -----------------------------------------------

  // GET /api/payment-methods?storeId=&mode=
  Future<List<PaymentMethod>> getPaymentMethods(
      {required String mode, int? storeId}) async {
    final resp = await _send(
      () => _http.get(
        _uri('/api/payment-methods').replace(queryParameters: {
          'mode': mode,
          if (storeId != null) 'storeId': '$storeId',
        }),
      ),
    );
    if (resp.statusCode == 200) {
      final list = jsonDecode(resp.body) as List<dynamic>;
      return list
          .map((e) => PaymentMethod.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw UnknownApiException(resp.statusCode, _extractMessage(resp));
  }

  // ---- Cart / order ----------------------------------------------------

  // POST /api/orders/quote
  Future<Quote> quote(List<CartItem> items,
      {int? storeId, String? token}) async {
    final resp = await _send(
      () => _http.post(
        _uri('/api/orders/quote'),
        headers: _headers(token: token),
        body: jsonEncode({
          if (storeId != null) 'storeId': storeId,
          'items': items.map((e) => e.toOrderLine()).toList(),
        }),
      ),
    );
    if (resp.statusCode == 200) {
      return Quote.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
    }
    final msg = _extractMessage(resp);
    if (resp.statusCode == 409) throw ProductNotSellableException(409, msg);
    throw UnknownApiException(resp.statusCode, msg);
  }

  // POST /api/orders
  Future<WahaOrder> createOrder(
    String orderId,
    List<CartItem> items, {
    int? storeId,
    String? username,
    String? token,
  }) async {
    final resp = await _send(
      () => _http.post(
        _uri('/api/orders'),
        headers: _headers(token: token),
        body: jsonEncode({
          if (storeId != null) 'storeId': storeId,
          'orderId': orderId,
          if (username != null) 'username': username,
          'items': items.map((e) => e.toOrderLine()).toList(),
        }),
      ),
    );
    if (resp.statusCode == 200) {
      return WahaOrder.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
    }
    final msg = _extractMessage(resp);
    if (resp.statusCode == 409) throw ProductNotSellableException(409, msg);
    throw UnknownApiException(resp.statusCode, msg);
  }

  // POST /api/orders/{id}/pay — Kiosk simulated
  Future<PayResult> pay(String orderId, {String? simulateOutcome}) async {
    final resp = await _send(
      () => _http.post(
        _uri('/api/orders/$orderId/pay'),
        headers: _headers(),
        body: jsonEncode({
          if (simulateOutcome != null) 'simulateOutcome': simulateOutcome,
        }),
      ),
    );
    if (resp.statusCode == 200) {
      return PayResult.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
    }
    final msg = _extractMessage(resp);
    if (resp.statusCode == 404) throw OrderNotFoundException(404, msg);
    if (resp.statusCode == 409) throw OrderAlreadyPaidException(409, msg);
    throw UnknownApiException(resp.statusCode, msg);
  }

  // POST /api/orders/{id}/payment-session
  // providerMode: 'REDIRECT' or 'QR_LINK' (kiosk).
  // QR_LINK responses include qrCodeDataUri + expiresAt.
  Future<PaymentSessionResult> createPaymentSession(String orderId,
      {required String provider, required String providerMode}) async {
    final resp = await _send(
      () => _http.post(
        _uri('/api/orders/$orderId/payment-session'),
        headers: _headers(),
        body: jsonEncode({'provider': provider, 'providerMode': providerMode}),
      ),
    );
    if (resp.statusCode == 200) {
      return PaymentSessionResult.fromJson(
          jsonDecode(resp.body) as Map<String, dynamic>);
    }
    final msg = _extractMessage(resp);
    if (resp.statusCode == 404) throw OrderNotFoundException(404, msg);
    if (resp.statusCode == 409) throw OrderAlreadyPaidException(409, msg);
    throw UnknownApiException(resp.statusCode, msg);
  }

  // ── Terminal payment endpoints (card-present, e.g. Geidea) ────────────────
  //
  // Same endpoints originally built for the waha_terminal NFC companion
  // app's create → poll → confirm flow; now called directly by the Kiosk
  // itself for Geidea's synchronous USB flow, skipping the polling step —
  // the Kiosk already knows the transaction result the moment the Geidea
  // SDK callback returns, so it confirms/cancels immediately instead of
  // waiting for a second device to do it over HTTP.

  Future<TerminalSession> createTerminalSession(String orderId,
      {String? token}) async {
    final resp = await _send(
      () => _http.post(_uri('/api/orders/$orderId/terminal-session'),
          headers: _headers(token: token)),
    );
    if (resp.statusCode == 200) {
      return TerminalSession.fromJson(
          jsonDecode(resp.body) as Map<String, dynamic>);
    }
    final msg = _extractMessage(resp);
    if (resp.statusCode == 404) throw OrderNotFoundException(404, msg);
    if (resp.statusCode == 409) throw OrderAlreadyPaidException(409, msg);
    throw UnknownApiException(resp.statusCode, msg);
  }

  // Terminal approved the transaction; marks the order PAID. notes carries
  // the full terminal transaction JSON (rrn, masked card number, terminal
  // id, ...) for audit/receipt purposes — free-form JSON server-side.
  Future<void> confirmTerminalSession(String sessionId,
      {required String authCode,
      required Map<String, dynamic> notes,
      String? token}) async {
    final resp = await _send(
      () => _http.post(
        _uri('/api/terminal-sessions/$sessionId/confirm'),
        headers: _headers(token: token),
        body: jsonEncode({'authCode': authCode, 'notes': notes}),
      ),
    );
    if (resp.statusCode == 200) return;
    throw UnknownApiException(resp.statusCode, _extractMessage(resp));
  }

  // Declined/error/gave up. Closes the PENDING record; does not preserve a
  // decline reason server-side (flagged to backend, accepted as-is for now).
  Future<void> cancelTerminalSession(String sessionId, {String? token}) async {
    await _send(() => _http.post(
        _uri('/api/terminal-sessions/$sessionId/cancel'),
        headers: _headers(token: token)));
  }

  // POST /api/orders/{id}/late-approval — the terminal approved after the
  // kiosk had given up. Answer is {"result": "PAID" | "IGNORED"}, both final
  // (the server pays the order only if it is still CREATED, young enough and
  // the amount matches). Throws [NetworkException] or [UnknownApiException]
  // for anything that may be retried; a 4xx other than 401 is final too and
  // is returned as the text "REJECTED".
  Future<String> reportLateApproval(
    String orderId, {
    required double amount,
    required String rrn,
    String? approvalCode,
    String? terminalId,
    String? token,
  }) async {
    final resp = await _send(
      () => _http.post(
        _uri('/api/orders/$orderId/late-approval'),
        headers: _headers(token: token),
        body: jsonEncode({
          'amount': amount,
          'rrn': rrn,
          if (approvalCode != null) 'approvalCode': approvalCode,
          if (terminalId != null) 'terminalId': terminalId,
        }),
      ),
    );
    if (resp.statusCode == 200) {
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      return (body['result'] as String?) ?? 'UNKNOWN';
    }
    if (resp.statusCode >= 400 && resp.statusCode < 500 && resp.statusCode != 401) {
      return 'REJECTED';
    }
    throw UnknownApiException(resp.statusCode, _extractMessage(resp));
  }

  // POST /api/kiosk/heartbeat — sign of life while the device is otherwise
  // idle. Only sent when the organization property heartbeat_minutes is above 0.
  Future<void> kioskHeartbeat(String token) async {
    final resp = await _send(
      () => _http.post(
        _uri('/api/kiosk/heartbeat'),
        headers: _headers(token: token),
        body: jsonEncode({'appVersion': AppInfo.version}),
      ),
    );
    if (resp.statusCode != 200) {
      throw UnknownApiException(resp.statusCode, _extractMessage(resp));
    }
  }

  // GET /api/orders/{id}
  Future<WahaOrder> getOrder(String orderId) async {
    final resp = await _send(() => _http.get(_uri('/api/orders/$orderId')));
    if (resp.statusCode == 200) {
      return WahaOrder.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
    }
    final msg = _extractMessage(resp);
    if (resp.statusCode == 404) throw OrderNotFoundException(404, msg);
    throw UnknownApiException(resp.statusCode, msg);
  }

  // ---- Admin edit endpoints -------------------------------------------

  // GET arbitrary resource URL (relative path) — downloads raw text content.
  // Used to fetch landing page HTML for local caching.
  Future<String> fetchResourceContent(String resourceUrl, String? token) async {
    final resp = await _send(
      () => _http.get(_uri(resourceUrl), headers: _headers(token: token)),
    );
    if (resp.statusCode == 200) return utf8.decode(resp.bodyBytes);
    throw UnknownApiException(resp.statusCode, _extractMessage(resp));
  }

  // GET /api/landing/{pageKey} — resolves current-store-vs-global landing page.
  // Returns null when no page is configured (404).
  Future<LandingPageInfo?> getLandingPage(String pageKey, String? token) async {
    final resp = await _send(
      () => _http.get(_uri('/api/landing/$pageKey'),
          headers: _headers(token: token)),
    );
    if (resp.statusCode == 404) return null;
    if (resp.statusCode == 200) {
      return LandingPageInfo.fromJson(
          jsonDecode(resp.body) as Map<String, dynamic>);
    }
    throw UnknownApiException(resp.statusCode, _extractMessage(resp));
  }
}

class PaymentSessionResult {
  final String redirectUrl;
  final String? qrCodeDataUri;
  final DateTime? expiresAt;

  const PaymentSessionResult({
    required this.redirectUrl,
    this.qrCodeDataUri,
    this.expiresAt,
  });

  factory PaymentSessionResult.fromJson(Map<String, dynamic> json) =>
      PaymentSessionResult(
        redirectUrl: json['redirectUrl'] as String,
        qrCodeDataUri: json['qrCodeDataUri'] as String?,
        expiresAt: json['expiresAt'] != null
            ? DateTime.parse(json['expiresAt'] as String)
            : null,
      );
}

class AdminPaymentMethodView {
  final int id;
  final String key;
  final Map<String, dynamic>? displayName;
  final String provider;
  final bool effectiveActive;
  final bool hasStoreOverride;

  const AdminPaymentMethodView({
    required this.id,
    required this.key,
    required this.displayName,
    required this.provider,
    required this.effectiveActive,
    required this.hasStoreOverride,
  });

  factory AdminPaymentMethodView.fromJson(Map<String, dynamic> json) =>
      AdminPaymentMethodView(
        id: (json['id'] as num).toInt(),
        key: json['key'] as String,
        displayName: json['displayName'] as Map<String, dynamic>?,
        provider: json['provider'] as String,
        effectiveActive: json['effectiveActive'] as bool? ?? true,
        hasStoreOverride: json['hasStoreOverride'] as bool? ?? false,
      );
}

class ResourceDirectory {
  final int id;
  final String name;
  const ResourceDirectory({required this.id, required this.name});
  factory ResourceDirectory.fromJson(Map<String, dynamic> json) =>
      ResourceDirectory(
          id: (json['id'] as num).toInt(), name: json['name'] as String);
}

class ResourceAsset {
  final int id;
  final String name;
  final String mimeType;
  final int sizeBytes;
  final String sha256;
  const ResourceAsset({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.sizeBytes,
    required this.sha256,
  });
  factory ResourceAsset.fromJson(Map<String, dynamic> json) => ResourceAsset(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String,
        mimeType: json['mimeType'] as String,
        sizeBytes: (json['sizeBytes'] as num).toInt(),
        sha256: json['sha256'] as String,
      );
  bool get isImage => mimeType.startsWith('image/');
  bool get isHtml {
    if (mimeType == 'text/html') return true;
    final n = name.toLowerCase();
    return n.endsWith('.html') || n.endsWith('.htm');
  }

  String publicUrl(String store, String dir) => '/resource/$store/$dir/$name';
}

class ReceiptInfoData {
  final int storeId;
  final String? nameAr;
  final String? nameEn;
  final String? addressText;
  final String? vatNumber;
  final String? crNumber;
  final int? logoResourceId;
  final String? unpaidInvoiceTitle;
  final String? paidInvoiceTitle;

  const ReceiptInfoData({
    required this.storeId,
    this.nameAr,
    this.nameEn,
    this.addressText,
    this.vatNumber,
    this.crNumber,
    this.logoResourceId,
    this.unpaidInvoiceTitle,
    this.paidInvoiceTitle,
  });

  factory ReceiptInfoData.fromJson(Map<String, dynamic> json) =>
      ReceiptInfoData(
        storeId: (json['storeId'] as num).toInt(),
        nameAr: json['nameAr'] as String?,
        nameEn: json['nameEn'] as String?,
        addressText: json['addressText'] as String?,
        vatNumber: json['vatNumber'] as String?,
        crNumber: json['crNumber'] as String?,
        logoResourceId: json['logoResourceId'] == null
            ? null
            : (json['logoResourceId'] as num).toInt(),
        unpaidInvoiceTitle: json['unpaidInvoiceTitle'] as String?,
        paidInvoiceTitle: json['paidInvoiceTitle'] as String?,
      );
}

class LandingPageInfo {
  final String pageKey;
  final String scope; // "local" | "global"
  final String store;
  final String
      resourceUrl; // relative, e.g. /resource/root/pages/KIOSK_LANDING.html
  final String contentHash;

  const LandingPageInfo({
    required this.pageKey,
    required this.scope,
    required this.store,
    required this.resourceUrl,
    required this.contentHash,
  });

  factory LandingPageInfo.fromJson(Map<String, dynamic> json) =>
      LandingPageInfo(
        pageKey: json['page_key'] as String,
        scope: json['scope'] as String,
        store: json['store'] as String,
        resourceUrl: json['resource_url'] as String,
        contentHash: json['content_hash'] as String,
      );
}

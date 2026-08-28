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
import 'api_exceptions.dart';

class ApiClient {
  final http.Client _http;
  ApiClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  Uri _uri(String path) => Uri.parse('${AppConfig.apiBaseUrl}$path');

  Map<String, String> _headers({String? token}) => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  /// Every non-2xx body is {"message": "..."}. Pulls that out, falling back
  /// to a generic string if the body doesn't parse.
  String _extractMessage(http.Response resp) {
    try {
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      return body['message'] as String? ?? 'Request failed (${resp.statusCode})';
    } catch (_) {
      return 'Request failed (${resp.statusCode})';
    }
  }

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request();
    } catch (e) {
      throw NetworkException(e);
    }
  }

  // ---- Auth --------------------------------------------------------

  // POST /api/auth/register
  Future<AuthSession> register(String username, String password,
      {Map<String, String>? sessionProperties}) async {
    final resp = await _send(
      () => _http.post(
        _uri('/api/auth/register'),
        headers: _headers(),
        body: jsonEncode({
          'username': username,
          'password': password,
          if (sessionProperties != null) 'sessionProperties': sessionProperties,
        }),
      ),
    );
    if (resp.statusCode == 200) {
      return AuthSession.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
    }
    final msg = _extractMessage(resp);
    if (resp.statusCode == 409) throw UsernameTakenException(409, msg);
    throw UnknownApiException(resp.statusCode, msg);
  }

  // POST /api/auth/login
  Future<AuthSession> login(String username, String password,
      {Map<String, String>? sessionProperties}) async {
    final resp = await _send(
      () => _http.post(
        _uri('/api/auth/login'),
        headers: _headers(),
        body: jsonEncode({
          'username': username,
          'password': password,
          if (sessionProperties != null) 'sessionProperties': sessionProperties,
        }),
      ),
    );
    if (resp.statusCode == 200) {
      return AuthSession.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
    }
    final msg = _extractMessage(resp);
    if (resp.statusCode == 401) throw UnauthorizedException(401, msg);
    throw UnknownApiException(resp.statusCode, msg);
  }

  // POST /api/auth/guest — Shopping mode only, creates throwaway account
  Future<AuthSession> guest() async {
    final resp = await _send(
      () => _http.post(_uri('/api/auth/guest'), headers: _headers()),
    );
    if (resp.statusCode == 200) {
      return AuthSession.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
    }
    throw UnknownApiException(resp.statusCode, _extractMessage(resp));
  }

  // POST /api/auth/logout
  Future<void> logout(String token) async {
    final resp = await _send(
      () => _http.post(_uri('/api/auth/logout'), headers: _headers(token: token)),
    );
    if (resp.statusCode == 200) return;
    final msg = _extractMessage(resp);
    if (resp.statusCode == 401) throw UnauthorizedException(401, msg);
    throw UnknownApiException(resp.statusCode, msg);
  }

  // GET /api/auth/me — session check on app start
  Future<AuthSession> me(String token) async {
    final resp = await _send(
      () => _http.get(_uri('/api/auth/me'), headers: _headers(token: token)),
    );
    if (resp.statusCode == 200) {
      return AuthSession.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
    }
    final msg = _extractMessage(resp);
    if (resp.statusCode == 401) throw UnauthorizedException(401, msg);
    throw UnknownApiException(resp.statusCode, msg);
  }

  // POST /api/auth/store
  Future<AuthSession> selectStore(String token, int storeId,
      {Map<String, String>? sessionProperties}) async {
    final resp = await _send(
      () => _http.post(
        _uri('/api/auth/store'),
        headers: _headers(token: token),
        body: jsonEncode({
          'storeId': storeId,
          if (sessionProperties != null) 'sessionProperties': sessionProperties,
        }),
      ),
    );
    if (resp.statusCode == 200) {
      return AuthSession.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
    }
    final msg = _extractMessage(resp);
    if (resp.statusCode == 401) throw UnauthorizedException(401, msg);
    throw UnknownApiException(resp.statusCode, msg);
  }

  // GET /api/config — public, no auth. Returns system_properties as key→value map.
  Future<Map<String, String>> getConfig() async {
    try {
      final resp = await _http.get(_uri('/api/config')).timeout(const Duration(seconds: 5));
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
      return list.map((e) => Store.fromJson(e as Map<String, dynamic>)).toList();
    }
    throw UnknownApiException(resp.statusCode, _extractMessage(resp));
  }

  // GET /api/stores/admin — admin variant; returns full store tree including
  // non-public nodes. Requires MANAGE_STORES permission on the server.
  Future<List<Store>> getAdminStores(String token) async {
    final resp = await _send(
      () => _http.get(_uri('/api/stores/admin'), headers: _headers(token: token)),
    );
    if (resp.statusCode == 200) {
      final list = jsonDecode(resp.body) as List<dynamic>;
      return list.map((e) => Store.fromJson(e as Map<String, dynamic>)).toList();
    }
    final msg = _extractMessage(resp);
    if (resp.statusCode == 401) throw UnauthorizedException(401, msg);
    throw UnknownApiException(resp.statusCode, msg);
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
      return ProductPage.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
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
      return ProductPage.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
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
      return list.map((e) => PaymentMethod.fromJson(e as Map<String, dynamic>)).toList();
    }
    throw UnknownApiException(resp.statusCode, _extractMessage(resp));
  }

  // PUT /api/config — update system properties (requires MANAGE_STORES)
  Future<void> updateConfig(Map<String, String> updates, {required String token}) async {
    final resp = await _send(
      () => _http.put(
        _uri('/api/config'),
        headers: _headers(token: token),
        body: jsonEncode(updates),
      ),
    );
    if (resp.statusCode == 200) return;
    throw UnknownApiException(resp.statusCode, _extractMessage(resp));
  }

  // GET /api/payment-methods/admin?storeId= — all methods with store active state
  Future<List<AdminPaymentMethodView>> getAdminPaymentMethods({int? storeId, String? token}) async {
    final resp = await _send(
      () => _http.get(
        _uri('/api/payment-methods/admin').replace(queryParameters: {
          if (storeId != null) 'storeId': '$storeId',
        }),
        headers: _headers(token: token),
      ),
    );
    if (resp.statusCode == 200) {
      final list = jsonDecode(resp.body) as List<dynamic>;
      return list.map((e) => AdminPaymentMethodView.fromJson(e as Map<String, dynamic>)).toList();
    }
    throw UnknownApiException(resp.statusCode, _extractMessage(resp));
  }

  // PUT /api/payment-methods/{id}/store-active?active=&storeId=
  Future<void> setPaymentMethodStoreActive(int id, {required bool active, int? storeId, String? token}) async {
    final resp = await _send(
      () => _http.put(
        _uri('/api/payment-methods/$id/store-active').replace(queryParameters: {
          'active': '$active',
          if (storeId != null) 'storeId': '$storeId',
        }),
        headers: _headers(token: token),
      ),
    );
    if (resp.statusCode == 200) return;
    throw UnknownApiException(resp.statusCode, _extractMessage(resp));
  }

  // ---- Cart / order ----------------------------------------------------

  // POST /api/orders/quote
  Future<Quote> quote(List<CartItem> items, {int? storeId, String? token}) async {
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

  // GET /api/orders?storeId=&page=&size= — paginated order history, newest first
  Future<List<WahaOrder>> getOrderHistory(String token,
      {int? storeId, int page = 0, int size = 10}) async {
    final resp = await _send(
      () => _http.get(
        _uri('/api/orders').replace(queryParameters: {
          if (storeId != null) 'storeId': '$storeId',
          'page': '$page',
          'size': '$size',
        }),
        headers: _headers(token: token),
      ),
    );
    if (resp.statusCode == 200) {
      final list = jsonDecode(resp.body) as List<dynamic>;
      return list.map((e) => WahaOrder.fromJson(e as Map<String, dynamic>)).toList();
    }
    throw UnknownApiException(resp.statusCode, _extractMessage(resp));
  }

  // DELETE /api/orders/{id} — user cancellation (CREATED only)
  Future<void> cancelOrder(String token, String orderId) async {
    final resp = await _send(
      () => _http.delete(_uri('/api/orders/$orderId'), headers: _headers(token: token)),
    );
    if (resp.statusCode == 200 || resp.statusCode == 204) return;
    final msg = _extractMessage(resp);
    if (resp.statusCode == 404) throw OrderNotFoundException(404, msg);
    if (resp.statusCode == 409) throw OrderAlreadyPaidException(409, msg);
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
  // providerMode: 'REDIRECT' (normal/shopping) or 'QR_LINK' (kiosk).
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

  // ── Terminal payment endpoints ────────────────────────────────────────────

  Future<String> createTerminalSession(String orderId) async {
    final resp = await _send(
      () => _http.post(_uri('/api/orders/$orderId/terminal-session'), headers: _headers()),
    );
    if (resp.statusCode == 200) {
      return (jsonDecode(resp.body) as Map<String, dynamic>)['id'] as String;
    }
    final msg = _extractMessage(resp);
    if (resp.statusCode == 409) throw OrderAlreadyPaidException(409, msg);
    throw UnknownApiException(resp.statusCode, msg);
  }

  Future<String> getTerminalSessionStatus(String sessionId) async {
    final resp = await _send(() => _http.get(_uri('/api/terminal-sessions/$sessionId')));
    if (resp.statusCode == 200) {
      return (jsonDecode(resp.body) as Map<String, dynamic>)['status'] as String;
    }
    throw UnknownApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<void> cancelTerminalSession(String sessionId) async {
    await _send(() => _http.post(_uri('/api/terminal-sessions/$sessionId/cancel'), headers: _headers()));
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

  // ── Odoo admin endpoints ──────────────────────────────────────────────────

  Future<Map<String, dynamic>> odooStatus(String token, {int? storeId}) async {
    final uri = _uri('/api/admin/odoo/status')
        .replace(queryParameters: storeId != null ? {'storeId': '$storeId'} : null);
    final resp = await _send(() => _http.get(uri, headers: _headers(token: token)));
    if (resp.statusCode == 200) return jsonDecode(resp.body) as Map<String, dynamic>;
    throw UnknownApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<void> oodooConfigure(String token, String baseUrl, String apiKey,
      String username, {String? customerOverride, int? storeId}) async {
    final uri = _uri('/api/admin/odoo/configure')
        .replace(queryParameters: storeId != null ? {'storeId': '$storeId'} : null);
    final body = <String, dynamic>{
      'baseUrl': baseUrl,
      'apiKey': apiKey,
      'username': username,
      if (customerOverride != null && customerOverride.isNotEmpty)
        'customerOverride': customerOverride,
    };
    final resp = await _send(
      () => _http.post(uri,
          headers: _headers(token: token),
          body: jsonEncode(body)),
    );
    if (resp.statusCode != 200) throw UnknownApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<int> oodooPullCategories(String token, {int? storeId}) async {
    final uri = _uri('/api/admin/odoo/pull/categories')
        .replace(queryParameters: storeId != null ? {'storeId': '$storeId'} : null);
    final resp = await _send(() => _http.post(uri, headers: _headers(token: token)));
    if (resp.statusCode == 200) {
      return (jsonDecode(resp.body) as Map<String, dynamic>)['pulled'] as int? ?? 0;
    }
    throw UnknownApiException(resp.statusCode, _extractMessage(resp));
  }

  /// Returns (pulled, visible) — pulled = new/updated from Odoo, visible = total accessible to store.
  Future<(int, int)> oodooPullProducts(String token, {int? storeId}) async {
    final uri = _uri('/api/admin/odoo/pull/products')
        .replace(queryParameters: storeId != null ? {'storeId': '$storeId'} : null);
    final resp = await _send(() => _http.post(uri, headers: _headers(token: token)));
    if (resp.statusCode == 200) {
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      return (body['pulled'] as int? ?? 0, body['visible'] as int? ?? 0);
    }
    throw UnknownApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<int> oodooPushOrders(String token, {int? storeId}) async {
    final uri = _uri('/api/admin/odoo/push/orders')
        .replace(queryParameters: storeId != null ? {'storeId': '$storeId'} : null);
    final resp = await _send(() => _http.post(uri, headers: _headers(token: token)));
    if (resp.statusCode == 200) {
      return (jsonDecode(resp.body) as Map<String, dynamic>)['pushed'] as int? ?? 0;
    }
    throw UnknownApiException(resp.statusCode, _extractMessage(resp));
  }

  // ---- Resource Library -----------------------------------------------

  Future<List<ResourceDirectory>> getDirectories(String store, String token) async {
    final resp = await _send(
      () => _http.get(_uri('/api/resources/$store/directories'), headers: _headers(token: token)),
    );
    if (resp.statusCode == 200) {
      return (jsonDecode(resp.body) as List)
          .map((e) => ResourceDirectory.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw UnknownApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<ResourceDirectory> createDirectory(String store, String name, String token) async {
    final resp = await _send(
      () => _http.post(
        _uri('/api/resources/$store/directories'),
        headers: _headers(token: token),
        body: jsonEncode({'name': name}),
      ),
    );
    if (resp.statusCode == 200) {
      return ResourceDirectory.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
    }
    throw UnknownApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<List<ResourceAsset>> getAssets(String store, String dir, String token) async {
    final resp = await _send(
      () => _http.get(_uri('/api/resources/$store/directories/$dir'), headers: _headers(token: token)),
    );
    if (resp.statusCode == 200) {
      return (jsonDecode(resp.body) as List)
          .map((e) => ResourceAsset.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw UnknownApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<ResourceAsset> uploadAsset(
      String store, String dir, List<int> bytes, String filename, String mimeType, String token,
      {String? nameOverride}) async {
    final uri = _uri('/api/resources/$store/directories/$dir');
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..files.add(http.MultipartFile.fromBytes('file', bytes,
          filename: filename, contentType: http.MediaType.parse(mimeType)));
    if (nameOverride != null) request.fields['name'] = nameOverride;

    http.StreamedResponse streamed;
    try {
      streamed = await _http.send(request);
    } catch (e) {
      throw NetworkException(e);
    }
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode == 200) {
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      return ResourceAsset(
        id: 0,
        name: body['name'] as String,
        mimeType: mimeType,
        sizeBytes: bytes.length,
        sha256: body['sha256'] as String,
      );
    }
    throw UnknownApiException(resp.statusCode, _extractMessage(resp));
  }

  Future<void> deleteAsset(String store, String dir, String name, String token) async {
    final resp = await _send(
      () => _http.delete(_uri('/api/resources/$store/directories/$dir/$name'),
          headers: _headers(token: token)),
    );
    if (resp.statusCode == 200) return;
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
      ResourceDirectory(id: (json['id'] as num).toInt(), name: json['name'] as String);
}

class ResourceAsset {
  final int id;
  final String name;
  final String mimeType;
  final int sizeBytes;
  final String sha256;
  const ResourceAsset({
    required this.id, required this.name, required this.mimeType,
    required this.sizeBytes, required this.sha256,
  });
  factory ResourceAsset.fromJson(Map<String, dynamic> json) => ResourceAsset(
    id: (json['id'] as num).toInt(),
    name: json['name'] as String,
    mimeType: json['mimeType'] as String,
    sizeBytes: (json['sizeBytes'] as num).toInt(),
    sha256: json['sha256'] as String,
  );
  bool get isImage => mimeType.startsWith('image/');
  bool get isHtml => mimeType == 'text/html';
  String publicUrl(String store, String dir) => '/resource/$store/$dir/$name';
}

class LandingPageInfo {
  final String pageKey;
  final String scope; // "local" | "global"
  final String store;
  final String resourceUrl; // relative, e.g. /resource/root/pages/KIOSK_LANDING.html
  final String contentHash;

  const LandingPageInfo({
    required this.pageKey,
    required this.scope,
    required this.store,
    required this.resourceUrl,
    required this.contentHash,
  });

  factory LandingPageInfo.fromJson(Map<String, dynamic> json) => LandingPageInfo(
    pageKey: json['page_key'] as String,
    scope: json['scope'] as String,
    store: json['store'] as String,
    resourceUrl: json['resource_url'] as String,
    contentHash: json['content_hash'] as String,
  );
}

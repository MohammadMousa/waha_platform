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

  // GET /api/stores
  Future<List<Store>> getStores() async {
    final resp = await _send(() => _http.get(_uri('/api/stores')));
    if (resp.statusCode == 200) {
      final list = jsonDecode(resp.body) as List<dynamic>;
      return list.map((e) => Store.fromJson(e as Map<String, dynamic>)).toList();
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

  // GET /api/orders?page=&size= — paginated order history, newest first
  Future<List<WahaOrder>> getOrderHistory(String token,
      {int page = 0, int size = 10}) async {
    final resp = await _send(
      () => _http.get(
        _uri('/api/orders')
            .replace(queryParameters: {'page': '$page', 'size': '$size'}),
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

  // POST /api/orders/{id}/payment-session — Normal/Shopping real payment
  Future<String> createPaymentSession(String orderId, {required String provider}) async {
    final resp = await _send(
      () => _http.post(
        _uri('/api/orders/$orderId/payment-session'),
        headers: _headers(),
        body: jsonEncode({'provider': provider}),
      ),
    );
    if (resp.statusCode == 200) {
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      return body['redirectUrl'] as String;
    }
    final msg = _extractMessage(resp);
    if (resp.statusCode == 404) throw OrderNotFoundException(404, msg);
    if (resp.statusCode == 409) throw OrderAlreadyPaidException(409, msg);
    throw UnknownApiException(resp.statusCode, msg);
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
}

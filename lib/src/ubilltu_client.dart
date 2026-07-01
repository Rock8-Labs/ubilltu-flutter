import 'dart:convert';

import 'package:http/http.dart' as http;

import 'exceptions.dart';
import 'models.dart';

/// A client for the ubilltu subscription commerce API (customer/storefront plane).
///
/// Every request is scoped to a tenant via the `X-Storefront-Slug` header. After
/// [login], the bearer token is attached to subsequent requests automatically.
///
/// ```dart
/// final client = UbilltuClient(storefrontSlug: 'my-store');
/// await client.login('user@example.com', 'password');
/// final plans = await client.listPlans();
/// ```
class UbilltuClient {
  UbilltuClient({
    required this.storefrontSlug,
    this.baseUrl = 'https://api.ubilltu.com',
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  /// The tenant storefront slug, sent as the `X-Storefront-Slug` header.
  final String storefrontSlug;

  /// API base URL. Defaults to production.
  final String baseUrl;

  final http.Client _http;

  UbilltuTokens? _tokens;

  /// The active session tokens, or `null` if not authenticated.
  UbilltuTokens? get tokens => _tokens;

  /// Restore a session from previously persisted tokens (e.g. secure storage).
  void restoreSession(UbilltuTokens tokens) => _tokens = tokens;

  /// Whether a session is currently active.
  bool get isAuthenticated =>
      _tokens != null && _tokens!.accessToken.isNotEmpty;

  // ---------------------------------------------------------------- Auth ----

  /// Authenticate a subscriber and store the session.
  Future<UbilltuTokens> login(String email, String password) async {
    final data = await _post(
      '/api/v1/auth/login',
      {'email': email, 'password': password},
      auth: false,
    );
    return _tokens = UbilltuTokens.fromJson(data);
  }

  /// Register a new subscriber. Stores the session if the API returns tokens.
  Future<UbilltuTokens> register({
    required String email,
    required String password,
    String? name,
  }) async {
    final data = await _post(
      '/api/v1/auth/register',
      {'email': email, 'password': password, if (name != null) 'name': name},
      auth: false,
    );
    final tokens = UbilltuTokens.fromJson(data);
    if (tokens.accessToken.isNotEmpty) _tokens = tokens;
    return tokens;
  }

  /// Refresh the access token using the stored refresh token.
  Future<UbilltuTokens> refresh() async {
    final rt = _tokens?.refreshToken;
    if (rt == null) throw UbilltuAuthException('No refresh token available.');
    final data =
        await _post('/api/v1/auth/refresh', {'refresh_token': rt}, auth: false);
    return _tokens = UbilltuTokens.fromJson(data);
  }

  /// Clear the local session. Does not revoke the token server-side.
  void logout() => _tokens = null;

  /// The authenticated subscriber's profile (`/auth/me`).
  Future<Map<String, dynamic>> me() => _get('/api/v1/auth/me');

  /// The authenticated subscriber's account details.
  Future<Map<String, dynamic>> account() => _get('/api/v1/account');

  // --------------------------------------------------------------- Plans ----

  /// List available plans from the tenant catalog.
  Future<Page<Plan>> listPlans() async =>
      Page.fromJson(await _get('/api/v1/plans'), Plan.fromJson);

  /// Fetch a single plan by id.
  Future<Plan> getPlan(String planId) async =>
      Plan.fromJson(await _get('/api/v1/plans/$planId'));

  // ------------------------------------------------------- Subscriptions ----

  /// List the subscriber's subscriptions.
  Future<Page<Subscription>> listSubscriptions() async => Page.fromJson(
        await _get('/api/v1/subscriptions'),
        Subscription.fromJson,
      );

  /// Fetch a single subscription.
  Future<Subscription> getSubscription(String id) async =>
      Subscription.fromJson(await _get('/api/v1/subscriptions/$id'));

  /// Subscribe to a plan. Extra fields (e.g. `billing_period`, `external_key`)
  /// may be supplied via [extra].
  Future<Subscription> subscribe(String planId,
      {Map<String, dynamic>? extra}) async {
    final data = await _post(
      '/api/v1/subscriptions',
      {'plan_id': planId, ...?extra},
    );
    return Subscription.fromJson(data);
  }

  /// Cancel a subscription.
  Future<void> cancelSubscription(String id) =>
      _delete('/api/v1/subscriptions/$id');

  /// Pause a subscription.
  Future<Subscription> pauseSubscription(String id) async =>
      Subscription.fromJson(
        await _post('/api/v1/subscriptions/$id/pause', const {}),
      );

  /// Resume a paused subscription.
  Future<Subscription> resumeSubscription(String id) async =>
      Subscription.fromJson(
        await _post('/api/v1/subscriptions/$id/resume', const {}),
      );

  /// Reactivate a cancelled subscription.
  Future<Subscription> reactivateSubscription(String id) async =>
      Subscription.fromJson(
        await _post('/api/v1/subscriptions/$id/reactivate', const {}),
      );

  // ------------------------------------------------------------ Invoices ----

  /// List the subscriber's invoices.
  Future<Page<Invoice>> listInvoices() async =>
      Page.fromJson(await _get('/api/v1/invoices'), Invoice.fromJson);

  /// Release the underlying HTTP client. Call when the client is no longer used.
  void close() => _http.close();

  // ----------------------------------------------------------- internals ----

  Map<String, String> _headers({bool json = false, bool auth = true}) {
    final h = <String, String>{
      'X-Storefront-Slug': storefrontSlug,
      'Accept': 'application/json',
    };
    if (json) h['Content-Type'] = 'application/json';
    if (auth) {
      final t = _tokens?.accessToken;
      if (t == null || t.isEmpty) throw UbilltuAuthException();
      h['Authorization'] = 'Bearer $t';
    }
    return h;
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final res =
        await _http.get(Uri.parse('$baseUrl$path'), headers: _headers());
    return _decode(res);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    bool auth = true,
  }) async {
    final res = await _http.post(
      Uri.parse('$baseUrl$path'),
      headers: _headers(json: true, auth: auth),
      body: jsonEncode(body),
    );
    return _decode(res);
  }

  Future<void> _delete(String path) async {
    final res =
        await _http.delete(Uri.parse('$baseUrl$path'), headers: _headers());
    _decode(res, allowEmpty: true);
  }

  Map<String, dynamic> _decode(http.Response res, {bool allowEmpty = false}) {
    final ok = res.statusCode >= 200 && res.statusCode < 300;
    Map<String, dynamic>? parsed;
    if (res.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(res.body);
        parsed = decoded is Map<String, dynamic>
            ? decoded
            : <String, dynamic>{'data': decoded};
      } catch (_) {
        parsed = null;
      }
    }
    if (!ok) {
      final msg = parsed?['detail']?.toString() ??
          parsed?['message']?.toString() ??
          res.reasonPhrase ??
          'Request failed';
      throw UbilltuApiException(
        statusCode: res.statusCode,
        message: msg,
        body: parsed,
      );
    }
    return parsed ?? <String, dynamic>{};
  }
}

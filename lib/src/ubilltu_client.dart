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
  ///
  /// The API requires `tos_accepted` (the caller's user must accept the Terms of
  /// Service); it defaults to `true` here for convenience.
  Future<UbilltuTokens> register({
    required String email,
    required String password,
    String? name,
    bool tosAccepted = true,
  }) async {
    final data = await _post(
      '/api/v1/auth/register',
      {
        'email': email,
        'password': password,
        'tos_accepted': tosAccepted,
        if (name != null) 'name': name,
      },
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

  /// Update the subscriber's profile fields (e.g. `name`, `phone`).
  Future<Map<String, dynamic>> updateAccount(Map<String, dynamic> fields) =>
      _put('/api/v1/account', fields);

  /// The subscriber's outstanding balance + available credit.
  Future<AccountBalance> balance() async =>
      AccountBalance(await _get('/api/v1/account/balance'));

  /// The subscriber's usage metrics.
  Future<UsageMetrics> usage() async =>
      UsageMetrics(await _get('/api/v1/account/usage'));

  /// The subscriber's payment history.
  Future<Page<Payment>> listPayments() async =>
      Page.fromJson(await _get('/api/v1/account/payments'), Payment.fromJson);

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

  /// Change a subscription's plan (upgrade / downgrade / change billing period).
  ///
  /// [newPlanId] is the target plan name — the billing period is encoded in it
  /// (e.g. `premium-annual`). [policy] defaults to `END_OF_TERM` (deferred, no
  /// proration); pass `IMMEDIATE` to apply the change now.
  Future<Subscription> changePlan(
    String id,
    String newPlanId, {
    String policy = 'END_OF_TERM',
    String? priceList,
    String? effectiveDate,
  }) async {
    final data = await _put('/api/v1/subscriptions/$id', {
      'plan_id': newPlanId,
      'billing_policy': policy,
      if (priceList != null) 'price_list': priceList,
      if (effectiveDate != null) 'effective_date': effectiveDate,
    });
    return Subscription.fromJson(data);
  }

  /// Preview the pro-rata invoice for a plan change before committing to it.
  /// Pass [newPlan] to preview switching to that plan.
  Future<Map<String, dynamic>> previewChange(String id, {String? newPlan}) {
    final q =
        newPlan != null ? '?new_plan=${Uri.encodeQueryComponent(newPlan)}' : '';
    return _get('/api/v1/subscriptions/$id/dry-run$q');
  }

  // ------------------------------------------------------------ Invoices ----

  /// List the subscriber's invoices.
  Future<Page<Invoice>> listInvoices() async =>
      Page.fromJson(await _get('/api/v1/invoices'), Invoice.fromJson);

  /// Fetch a single invoice with line-item detail.
  Future<Map<String, dynamic>> getInvoice(String invoiceId) =>
      _get('/api/v1/invoices/$invoiceId');

  /// Download an invoice as PDF bytes.
  Future<List<int>> invoicePdf(String invoiceId) =>
      _getBytes('/api/v1/invoices/$invoiceId/pdf');

  // -------------------------------------------------------------- Payments --

  /// List the subscriber's saved payment methods (cards on file).
  Future<Page<PaymentMethod>> listPaymentMethods() async => Page.fromJson(
        await _get('/api/v1/payments/methods'),
        PaymentMethod.fromJson,
      );

  /// Start a zero-amount card-on-file setup. Returns `{redirect_url}` — send the
  /// customer to that hosted page to enter their card.
  Future<Map<String, dynamic>> setupPaymentMethod(
    String returnUrl, {
    bool isDefault = false,
  }) =>
      _post('/api/v1/payments/methods/setup', {
        'return_url': returnUrl,
        'is_default': isDefault,
      });

  /// Subscribe to a plan AND start payment collection in one call. Returns
  /// `{subscription_id, payment_id, redirect_url}` — the subscription exists
  /// immediately; send the customer to `redirect_url` to pay the first invoice.
  Future<Map<String, dynamic>> signup(String planId, String returnUrl) => _post(
        '/api/v1/subscriptions/signup',
        {'plan_id': planId, 'return_url': returnUrl},
      );

  /// Start a hosted checkout for an amount. Returns `{payment_id, redirect_url}`.
  Future<Map<String, dynamic>> checkout(
    num amount, {
    String currency = 'ZAR',
    String? invoiceId,
    String? subscriptionId,
  }) =>
      _post('/api/v1/payments/checkout', {
        'amount': amount,
        'currency': currency,
        if (invoiceId != null) 'invoice_id': invoiceId,
        if (subscriptionId != null) 'subscription_id': subscriptionId,
      });

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

  Future<Map<String, dynamic>> _put(
    String path,
    Map<String, dynamic> body,
  ) async {
    final res = await _http.put(
      Uri.parse('$baseUrl$path'),
      headers: _headers(json: true),
      body: jsonEncode(body),
    );
    return _decode(res);
  }

  Future<List<int>> _getBytes(String path) async {
    final res =
        await _http.get(Uri.parse('$baseUrl$path'), headers: _headers());
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _decode(res); // throws UbilltuApiException
    }
    return res.bodyBytes;
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
      final err = parsed?['error'];
      final msg = (err is Map ? err['message']?.toString() : null) ??
          parsed?['detail']?.toString() ??
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

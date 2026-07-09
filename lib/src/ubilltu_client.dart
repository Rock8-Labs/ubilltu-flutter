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
      auth: 'none',
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
      auth: 'none',
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
        await _post('/api/v1/auth/refresh', {'refresh_token': rt}, auth: 'none');
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
  Future<Page<Payment>> listPayments({int? page, int? perPage}) async =>
      Page.fromJson(
        await _get('/api/v1/account/payments${_pageQuery(page, perPage)}'),
        Payment.fromJson,
      );

  /// Right-to-erasure (GDPR Art. 17 / POPIA s24). Cancels subscriptions, scrubs
  /// PII, and pseudonymizes the account — IRREVERSIBLE. [confirmEmail] must match
  /// the account email; [confirmPhrase] must be exactly `"ERASE"`. Returns
  /// `{erasure_id, erased_fields}`.
  Future<Map<String, dynamic>> eraseAccount(
    String confirmEmail, {
    String confirmPhrase = 'ERASE',
  }) =>
      _post('/api/v1/account/erase', {
        'confirm_email': confirmEmail,
        'confirm_phrase': confirmPhrase,
      });

  // --------------------------------------------------------------- Plans ----

  /// List available plans. PUBLIC — works before [login] (the storefront slug is
  /// enough; the token is attached only if present).
  Future<Page<Plan>> listPlans({int? page, int? perPage}) async =>
      Page.fromJson(
        await _get('/api/v1/plans${_pageQuery(page, perPage)}', auth: 'optional'),
        Plan.fromJson,
      );

  /// Fetch a single plan by id. PUBLIC — works before [login].
  Future<Plan> getPlan(String planId) async =>
      Plan.fromJson(await _get('/api/v1/plans/$planId', auth: 'optional'));

  // ------------------------------------------------------- Subscriptions ----

  /// List the subscriber's subscriptions.
  Future<Page<Subscription>> listSubscriptions({int? page, int? perPage}) async =>
      Page.fromJson(
        await _get('/api/v1/subscriptions${_pageQuery(page, perPage)}'),
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

  /// Cancel a subscription. [policy] defaults to `END_OF_TERM` — the subscription
  /// keeps access until the period ends and reads as "Cancelling" (reactivatable).
  /// Pass `'IMMEDIATE'` to cancel now, or `null` to use the server default.
  Future<Map<String, dynamic>> cancelSubscription(
    String id, {
    String? policy = 'END_OF_TERM',
  }) async =>
      _decode(await _send(
        'DELETE',
        '/api/v1/subscriptions/$id',
        body: policy != null ? {'use_policy': policy} : null,
      ));

  /// Pause a subscription (schedules pause at end of period).
  Future<PauseResult> pauseSubscription(String id) async =>
      PauseResult(await _post('/api/v1/subscriptions/$id/pause', const {}));

  /// Resume a paused subscription.
  Future<PauseResult> resumeSubscription(String id) async =>
      PauseResult(await _post('/api/v1/subscriptions/$id/resume', const {}));

  /// Reactivate a cancelled subscription.
  Future<Subscription> reactivateSubscription(String id) async =>
      Subscription.fromJson(
        await _post('/api/v1/subscriptions/$id/reactivate', const {}),
      );

  /// Whether the customer may self-resume this (paused) subscription (SEC-019).
  Future<bool> selfResumeAllowed(String id) async {
    final r = await _get('/api/v1/subscriptions/$id/self-resume-allowed');
    return r['allowed'] == true;
  }

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
  Future<Page<Invoice>> listInvoices({int? page, int? perPage}) async =>
      Page.fromJson(
        await _get('/api/v1/invoices${_pageQuery(page, perPage)}'),
        Invoice.fromJson,
      );

  /// Fetch a single invoice with line-item detail.
  Future<Map<String, dynamic>> getInvoice(String invoiceId) =>
      _get('/api/v1/invoices/$invoiceId');

  /// Download an invoice as PDF bytes.
  Future<List<int>> invoicePdf(String invoiceId) =>
      _getBytes('/api/v1/invoices/$invoiceId/pdf');

  /// Render an invoice as branded HTML (string).
  Future<String> invoiceHtml(String invoiceId) async =>
      utf8.decode(await _getBytes('/api/v1/invoices/$invoiceId/html'));

  // ---------------------------------------------------------------- Family --

  /// The caller's family view (owner or member), or `null` if not in one.
  Future<Family?> getFamily() async {
    final fam = (await _get('/api/v1/me/family'))['family'];
    return fam is Map ? Family(fam.cast<String, dynamic>()) : null;
  }

  /// Owner removes a member from their family.
  Future<Map<String, dynamic>> removeFamilyMember(String memberId) =>
      _post('/api/v1/me/family/members/$memberId/remove', const {});

  /// Leave the family the caller currently belongs to (members only).
  Future<Map<String, dynamic>> leaveFamily() =>
      _post('/api/v1/me/family-memberships/leave', const {});

  /// Owner generates a fresh invite code (invalidates any existing one).
  Future<InviteCode> createFamilyInvite({int expiresInHours = 72}) async {
    final r = await _post(
      '/api/v1/me/family/invite',
      {'expires_in_hours': expiresInHours},
    );
    final data = r['data'];
    return InviteCode(data is Map ? data.cast<String, dynamic>() : const {});
  }

  /// List invite codes for the caller's owned family.
  Future<List<InviteCode>> listFamilyInvites() async {
    final data = (await _get('/api/v1/me/family/invites'))['data'];
    if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => InviteCode(e.cast<String, dynamic>()))
          .toList(growable: false);
    }
    return const [];
  }

  /// Owner revokes an invite code.
  Future<Map<String, dynamic>> revokeFamilyInvite(String code) =>
      _post('/api/v1/me/family/invite/$code/revoke', const {});

  /// Redeem an invite code to join a family (identity comes from the session).
  Future<Map<String, dynamic>> acceptFamilyInvite(String code) =>
      _post('/api/v1/me/family/invite/$code/accept', const {});

  /// Public preview of an invite code (no auth) — for a join page pre-login.
  Future<InvitePreview> validateInvite(String code) async {
    final preview =
        (await _get('/api/v1/invite/$code/validate', auth: 'none'))['preview'];
    return InvitePreview(
        preview is Map ? preview.cast<String, dynamic>() : const {});
  }

  // -------------------------------------------------------------- Payments --

  /// List the subscriber's saved payment methods (cards on file).
  Future<Page<PaymentMethod>> listPaymentMethods({int? page, int? perPage}) async =>
      Page.fromJson(
        await _get('/api/v1/payments/methods${_pageQuery(page, perPage)}'),
        PaymentMethod.fromJson,
      );

  /// Save a payment method from a PSP card token.
  Future<PaymentMethod> addPaymentMethod(
    String cardToken, {
    bool isDefault = false,
  }) async =>
      PaymentMethod(await _post('/api/v1/payments/methods', {
        'card_token': cardToken,
        'is_default': isDefault,
      }));

  /// Remove a saved payment method (re-promotes another card if it was default).
  Future<void> deletePaymentMethod(String methodId) =>
      _delete('/api/v1/payments/methods/$methodId');

  /// Make a saved payment method the account default.
  Future<Map<String, dynamic>> setDefaultPaymentMethod(String methodId) =>
      _put('/api/v1/payments/methods/$methodId/default', const {});

  /// Ensure the account default points at a real, chargeable card.
  Future<Map<String, dynamic>> reconcileDefaultPaymentMethod() =>
      _post('/api/v1/payments/methods/reconcile-default', const {});

  /// Fetch a single payment's live status (reconciles PENDING with the gateway).
  Future<Payment> getPayment(String paymentId) async =>
      Payment(await _get('/api/v1/payments/$paymentId'));

  /// Make an ad-hoc / one-off payment. [source] describes what to pay
  /// (`{type: 'ad_hoc', amount, currency, description}`, or `{type: 'invoice',
  /// invoice_id}` / `{type: 'addon', plan_id}`); [settlement] describes how
  /// (`{mode: 'saved', payment_method_id}` or `{mode: 'hosted', return_url}`).
  /// Returns the raw response (`status`, `requires_redirect`, `redirect_url`,
  /// `payment_id`).
  Future<Map<String, dynamic>> createOneOffPayment(
    Map<String, dynamic> source,
    Map<String, dynamic> settlement,
  ) =>
      _post('/api/v1/payments/one-off', {
        'source': source,
        'settlement': settlement,
      });

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

  /// [auth]: `'required'` (attach token, throw if missing), `'optional'`
  /// (attach if present), or `'none'` (never attach).
  Map<String, String> _headers({bool json = false, String auth = 'required'}) {
    final h = <String, String>{
      'X-Storefront-Slug': storefrontSlug,
      'Accept': 'application/json',
    };
    if (json) h['Content-Type'] = 'application/json';
    final t = _tokens?.accessToken;
    if (auth == 'required' && (t == null || t.isEmpty)) throw UbilltuAuthException();
    if (auth != 'none' && t != null && t.isNotEmpty) h['Authorization'] = 'Bearer $t';
    return h;
  }

  /// Build a `?page=&per_page=` suffix (empty when nothing is set).
  String _pageQuery(int? page, int? perPage) {
    final parts = <String>[];
    if (page != null) parts.add('page=$page');
    if (perPage != null) parts.add('per_page=$perPage');
    return parts.isEmpty ? '' : '?${parts.join('&')}';
  }

  Future<http.Response> _rawSend(
    String method,
    String path, {
    String? body,
    required String auth,
  }) {
    final uri = Uri.parse('$baseUrl$path');
    final headers = _headers(json: body != null, auth: auth);
    switch (method) {
      case 'GET':
        return _http.get(uri, headers: headers);
      case 'POST':
        return _http.post(uri, headers: headers, body: body);
      case 'PUT':
        return _http.put(uri, headers: headers, body: body);
      case 'DELETE':
        return _http.delete(uri, headers: headers, body: body);
      default:
        throw UbilltuException('Unsupported method $method');
    }
  }

  /// Send a request, transparently refreshing the token once on a 401 (docs
  /// recommend refresh-on-401) when a refresh token is present.
  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String auth = 'required',
    bool retry = true,
  }) async {
    final encoded = body != null ? jsonEncode(body) : null;
    var res = await _rawSend(method, path, body: encoded, auth: auth);
    if (res.statusCode == 401 &&
        retry &&
        auth != 'none' &&
        (_tokens?.refreshToken?.isNotEmpty ?? false)) {
      var refreshed = false;
      try {
        await refresh();
        refreshed = true;
      } catch (_) {
        // fall through and surface the original 401
      }
      if (refreshed) res = await _rawSend(method, path, body: encoded, auth: auth);
    }
    return res;
  }

  Future<Map<String, dynamic>> _get(String path, {String auth = 'required'}) async =>
      _decode(await _send('GET', path, auth: auth));

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    String auth = 'required',
  }) async =>
      _decode(await _send('POST', path, body: body, auth: auth));

  Future<Map<String, dynamic>> _put(
    String path,
    Map<String, dynamic> body,
  ) async =>
      _decode(await _send('PUT', path, body: body));

  Future<List<int>> _getBytes(String path) async {
    final res = await _send('GET', path);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      _decode(res); // throws UbilltuApiException
    }
    return res.bodyBytes;
  }

  Future<void> _delete(String path) async {
    _decode(await _send('DELETE', path), allowEmpty: true);
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

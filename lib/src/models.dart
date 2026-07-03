/// A paginated list envelope returned by ubilltu list endpoints
/// (`{items, total, page, per_page}`).
class Page<T> {
  Page({
    required this.items,
    required this.total,
    required this.page,
    required this.perPage,
  });

  final List<T> items;
  final int total;
  final int page;
  final int perPage;

  factory Page.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) fromItem,
  ) {
    final raw = (json['items'] as List<dynamic>? ?? const <dynamic>[]);
    return Page<T>(
      items: raw
          .map((e) => fromItem(e as Map<String, dynamic>))
          .toList(growable: false),
      total: (json['total'] as num?)?.toInt() ?? raw.length,
      page: (json['page'] as num?)?.toInt() ?? 1,
      perPage: (json['per_page'] as num?)?.toInt() ?? raw.length,
    );
  }
}

/// Auth tokens returned by login/register/refresh.
class UbilltuTokens {
  UbilltuTokens({required this.accessToken, this.refreshToken, this.tokenType});

  final String accessToken;
  final String? refreshToken;
  final String? tokenType;

  factory UbilltuTokens.fromJson(Map<String, dynamic> json) => UbilltuTokens(
        accessToken: (json['access_token'] ?? json['token'] ?? '') as String,
        refreshToken: json['refresh_token'] as String?,
        tokenType: json['token_type'] as String?,
      );
}

/// A subscription plan from the tenant catalog.
///
/// Typed getters cover the common fields; [raw] exposes the full payload for
/// anything not surfaced here.
class Plan {
  Plan(this.raw);

  final Map<String, dynamic> raw;

  // The API returns price/currency inside a `prices[]` array and the display
  // name in `product_name`; fall back to flat fields for safety.
  Map<String, dynamic> get _firstPrice {
    final prices = raw['prices'];
    if (prices is List && prices.isNotEmpty && prices.first is Map) {
      return (prices.first as Map).cast<String, dynamic>();
    }
    return const {};
  }

  String get id =>
      (raw['plan_id'] ?? raw['id'] ?? raw['plan_name'] ?? raw['name'] ?? '')
          .toString();
  String get name =>
      (raw['product_name'] ?? raw['plan_name'] ?? raw['name'] ?? '').toString();
  num? get price =>
      (raw['price'] ?? raw['amount'] ?? _firstPrice['amount']) as num?;
  String? get currency =>
      (raw['currency'] ?? _firstPrice['currency']) as String?;
  String? get billingPeriod => (raw['billing_period'] ??
      raw['billingPeriod'] ??
      _firstPrice['billing_period']) as String?;

  factory Plan.fromJson(Map<String, dynamic> json) => Plan(json);
}

/// A subscriber's subscription.
class Subscription {
  Subscription(this.raw);

  final Map<String, dynamic> raw;

  // The detail endpoint wraps it as {"subscription": {...}, "events": [...]};
  // the list returns it flat. Unwrap so both shapes parse.
  Map<String, dynamic> get _sub {
    final s = raw['subscription'];
    return s is Map ? s.cast<String, dynamic>() : raw;
  }

  String get id => (_sub['subscription_id'] ?? _sub['id'] ?? '').toString();
  String? get planName => (_sub['plan_name'] ?? _sub['planName']) as String?;
  String? get state => (_sub['state'] ?? _sub['status']) as String?;

  factory Subscription.fromJson(Map<String, dynamic> json) =>
      Subscription(json);
}

/// An invoice.
class Invoice {
  Invoice(this.raw);

  final Map<String, dynamic> raw;

  String get id => (raw['invoice_id'] ?? raw['id'] ?? '').toString();
  num? get amount => (raw['amount'] ?? raw['balance']) as num?;
  String? get currency => raw['currency'] as String?;
  String? get status => raw['status'] as String?;

  factory Invoice.fromJson(Map<String, dynamic> json) => Invoice(json);
}

/// A payment record.
class Payment {
  Payment(this.raw);

  final Map<String, dynamic> raw;

  String get id => (raw['payment_id'] ?? raw['id'] ?? '').toString();
  num? get amount => (raw['amount'] ?? raw['purchased_amount']) as num?;
  String? get currency => raw['currency'] as String?;
  String? get status => (raw['status'] ?? raw['state']) as String?;

  factory Payment.fromJson(Map<String, dynamic> json) => Payment(json);
}

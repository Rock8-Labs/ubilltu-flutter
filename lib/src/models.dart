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

  String get id =>
      (raw['id'] ?? raw['plan_id'] ?? raw['name'] ?? '').toString();
  String get name => (raw['name'] ?? raw['plan_name'] ?? '').toString();
  num? get price => (raw['price'] ?? raw['amount']) as num?;
  String? get currency => raw['currency'] as String?;
  String? get billingPeriod =>
      (raw['billing_period'] ?? raw['billingPeriod']) as String?;

  factory Plan.fromJson(Map<String, dynamic> json) => Plan(json);
}

/// A subscriber's subscription.
class Subscription {
  Subscription(this.raw);

  final Map<String, dynamic> raw;

  String get id => (raw['subscription_id'] ?? raw['id'] ?? '').toString();
  String? get planName => (raw['plan_name'] ?? raw['planName']) as String?;
  String? get state => (raw['state'] ?? raw['status']) as String?;

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

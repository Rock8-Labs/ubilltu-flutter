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

  /// Free-trial length in days, derived from a TRIAL phase if present.
  int? get trialDays {
    final phases = raw['phases'];
    if (phases is List) {
      for (final p in phases) {
        if (p is Map &&
            (p['phase_type'] ?? p['phaseType']) == 'TRIAL') {
          return (p['duration_length'] ?? p['durationLength']) as int?;
        }
      }
    }
    return (raw['trial_days'] ?? raw['trialDays']) as int?;
  }

  /// Plan features shown on the pricing page (API `plan_features` enrichment).
  List<String> get features =>
      (raw['features'] as List?)?.cast<String>() ?? const [];

  /// `"full_price"` | `"pro_rata"` — how the first period is charged.
  String? get billingMode =>
      (raw['billing_mode'] ?? raw['billingMode']) as String?;

  /// Anchor day-of-month; set only for pro-rata plans.
  int? get billingDay => (raw['billing_day'] ?? raw['billingDay']) as int?;

  /// Family/group config (`{enabled, includedSeats}`), or `null` if individual.
  Map<String, dynamic>? get familyConfig {
    final fc = raw['family_config'] ?? raw['familyConfig'];
    return fc is Map ? fc.cast<String, dynamic>() : null;
  }

  /// True when this plan is family/group-enabled.
  bool get isFamily => familyConfig?['enabled'] == true;

  /// True when the first period is charged pro-rata.
  bool get isProRata => (billingMode ?? '').toLowerCase() == 'pro_rata';

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
  String? get productName =>
      (_sub['product_name'] ?? _sub['productName']) as String?;
  String? get state => (_sub['state'] ?? _sub['status']) as String?;
  num? get price => _sub['price'] as num?;
  String? get currency => _sub['currency'] as String?;

  /// Future date => a scheduled end-of-term cancel (still ACTIVE until then).
  String? get cancelledDate =>
      (_sub['cancelled_date'] ?? _sub['cancelledDate']) as String?;
  String? get chargedThroughDate =>
      (_sub['charged_through_date'] ?? _sub['chargedThroughDate']) as String?;
  String? get billingEndDate =>
      (_sub['billing_end_date'] ?? _sub['billingEndDate']) as String?;

  /// Catalog price normalized to monthly, for MRR.
  num? get mrrMonthly => (_sub['mrr_monthly'] ?? _sub['mrrMonthly']) as num?;
  num? get lastPaymentAmount =>
      (_sub['last_payment_amount'] ?? _sub['lastPaymentAmount']) as num?;
  String? get lastPaymentDate =>
      (_sub['last_payment_date'] ?? _sub['lastPaymentDate']) as String?;
  String? get lastPaymentCurrency =>
      (_sub['last_payment_currency'] ?? _sub['lastPaymentCurrency']) as String?;

  /// Event stream (present on the detail endpoint); scheduled pauses live here.
  List<Map<String, dynamic>> get events {
    final e = raw['events'] ?? _sub['events'];
    if (e is List) {
      return e
          .whereType<Map>()
          .map((m) => m.cast<String, dynamic>())
          .toList(growable: false);
    }
    return const [];
  }

  /// A pending end-of-term cancel: [cancelledDate] set while still ACTIVE
  /// (keeps access until the date). Mirrors the storefront/portal "Cancelling".
  bool get isCancellationScheduled =>
      cancelledDate != null && (state ?? '').toUpperCase() == 'ACTIVE';

  /// Currently paused (Kill Bill BLOCKED). A *scheduled* future pause instead
  /// lives in [events] as a future PAUSE_* event.
  bool get isPaused => (state ?? '').toUpperCase() == 'BLOCKED';

  factory Subscription.fromJson(Map<String, dynamic> json) =>
      Subscription(json);
}

/// A single line on an invoice.
class InvoiceItem {
  InvoiceItem(this.raw);

  final Map<String, dynamic> raw;

  String? get description => raw['description'] as String?;
  String? get planName => (raw['plan_name'] ?? raw['planName']) as String?;
  String? get phase => raw['phase'] as String?;
  num? get amount => raw['amount'] as num?;
  String? get currency => raw['currency'] as String?;
  String? get startDate => (raw['start_date'] ?? raw['startDate']) as String?;
  String? get endDate => (raw['end_date'] ?? raw['endDate']) as String?;

  factory InvoiceItem.fromJson(Map<String, dynamic> json) => InvoiceItem(json);
}

/// An invoice.
class Invoice {
  Invoice(this.raw);

  final Map<String, dynamic> raw;

  String get id => (raw['invoice_id'] ?? raw['id'] ?? '').toString();
  num? get amount => (raw['amount'] ?? raw['balance']) as num?;
  String? get currency => raw['currency'] as String?;
  String? get status => raw['status'] as String?;

  String? get invoiceNumber =>
      (raw['invoice_number'] ?? raw['invoiceNumber']) as String?;
  String? get invoiceDate =>
      (raw['invoice_date'] ?? raw['invoiceDate']) as String?;
  num? get balance => raw['balance'] as num?;
  num? get creditAdj => (raw['credit_adj'] ?? raw['creditAdj']) as num?;
  num? get refundAdj => (raw['refund_adj'] ?? raw['refundAdj']) as num?;

  List<InvoiceItem> get items {
    final raws = raw['items'];
    if (raws is List) {
      return raws
          .whereType<Map>()
          .map((m) => InvoiceItem(m.cast<String, dynamic>()))
          .toList(growable: false);
    }
    return const [];
  }

  /// The zero-total, zero-item invoice Kill Bill commits on subscription setup
  /// (findings #1) — useful to filter from a customer-facing list.
  bool get isEmpty => (amount ?? 0) == 0 && items.isEmpty;

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

  String? get paymentNumber =>
      (raw['payment_number'] ?? raw['paymentNumber']) as String?;
  String? get paymentDate =>
      (raw['payment_date'] ?? raw['paymentDate']) as String?;
  String? get invoiceId => (raw['invoice_id'] ?? raw['invoiceId']) as String?;
  String? get invoiceNumber =>
      (raw['invoice_number'] ?? raw['invoiceNumber']) as String?;
  num? get refundedAmount =>
      (raw['refunded_amount'] ?? raw['refundedAmount']) as num?;
  String? get description => raw['description'] as String?;

  factory Payment.fromJson(Map<String, dynamic> json) => Payment(json);
}

/// A saved payment method (card on file).
class PaymentMethod {
  PaymentMethod(this.raw);

  final Map<String, dynamic> raw;

  String get id => (raw['payment_method_id'] ?? raw['id'] ?? '').toString();
  bool get isDefault => raw['is_default'] == true;
  String? get cardBrand => (raw['card_brand'] ?? raw['card_type']) as String?;
  String? get cardLast4 => (raw['card_last_four'] ?? raw['last4']) as String?;
  int? get expiryMonth => raw['expiry_month'] as int?;
  int? get expiryYear => raw['expiry_year'] as int?;

  factory PaymentMethod.fromJson(Map<String, dynamic> json) =>
      PaymentMethod(json);
}

/// Outstanding balance + available credit for the account.
class AccountBalance {
  AccountBalance(this.raw);

  final Map<String, dynamic> raw;

  /// What's owed (Kill Bill accountBalance).
  num? get balance => raw['balance'] as num?;

  /// Available credit / CBA (offsets future invoices, e.g. from a downgrade).
  num? get credit => raw['credit'] as num?;
  String? get currency => raw['currency'] as String?;

  factory AccountBalance.fromJson(Map<String, dynamic> json) =>
      AccountBalance(json);
}

/// Account usage/rollup metrics (`GET /account/usage`).
class UsageMetrics {
  UsageMetrics(this.raw);

  final Map<String, dynamic> raw;

  int? get totalSubscriptions =>
      (raw['total_subscriptions'] ?? raw['totalSubscriptions']) as int?;
  int? get activeSubscriptions =>
      (raw['active_subscriptions'] ?? raw['activeSubscriptions']) as int?;
  int? get totalInvoices =>
      (raw['total_invoices'] ?? raw['totalInvoices']) as int?;
  int? get unpaidInvoices =>
      (raw['unpaid_invoices'] ?? raw['unpaidInvoices']) as int?;
  num? get totalSpent => (raw['total_spent'] ?? raw['totalSpent']) as num?;
  String? get currency => raw['currency'] as String?;

  factory UsageMetrics.fromJson(Map<String, dynamic> json) =>
      UsageMetrics(json);
}

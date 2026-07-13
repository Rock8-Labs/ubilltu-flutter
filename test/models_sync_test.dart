import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:ubilltu/ubilltu.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

void main() {
  group('Tier-1 model sync', () {
    test('Plan surfaces features, billing mode and family config', () {
      final p = Plan({
        'plan_name': 'feature-monthly',
        'product_name': 'Feature',
        'prices': [
          {'amount': 250, 'currency': 'ZAR', 'billing_period': 'MONTHLY'}
        ],
        'features': ['Unlimited boards', 'Priority support'],
        'billingMode': 'pro_rata',
        'billingDay': 1,
        'familyConfig': {'enabled': true, 'includedSeats': 5},
      });
      expect(p.features, ['Unlimited boards', 'Priority support']);
      expect(p.billingMode, 'pro_rata');
      expect(p.billingDay, 1);
      expect(p.isProRata, isTrue);
      expect(p.familyConfig, {'enabled': true, 'includedSeats': 5});
      expect(p.isFamily, isTrue);
    });

    test('Plan defaults when unenriched', () {
      final p = Plan({'plan_name': 'basic-monthly', 'price': 99});
      expect(p.features, isEmpty);
      expect(p.billingMode, isNull);
      expect(p.familyConfig, isNull);
      expect(p.isFamily, isFalse);
      expect(p.isProRata, isFalse);
    });

    test('Subscription surfaces scheduled cancel + mrr and detects cancelling',
        () {
      final s = Subscription({
        'subscription': {
          'subscription_id': 's1',
          'state': 'ACTIVE',
          'cancelled_date': '2026-09-01',
          'charged_through_date': '2026-09-01',
          'mrr_monthly': 250,
          'last_payment_amount': 250,
        },
        'events': [
          {'eventType': 'STOP_ENTITLEMENT'}
        ],
      });
      expect(s.cancelledDate, '2026-09-01');
      expect(s.chargedThroughDate, '2026-09-01');
      expect(s.mrrMonthly, 250);
      expect(s.events, hasLength(1));
      expect(s.isCancellationScheduled, isTrue);
      expect(s.isPaused, isFalse);
    });

    test('Subscription BLOCKED is paused, not cancelling', () {
      final s = Subscription({'subscription_id': 's3', 'state': 'BLOCKED'});
      expect(s.isPaused, isTrue);
      expect(s.isCancellationScheduled, isFalse);
    });

    test('Invoice maps line items + balance + empty flag', () {
      final inv = Invoice({
        'invoice_id': 'i1',
        'invoice_number': '1001',
        'amount': 250,
        'balance': 0,
        'credit_adj': -50,
        'items': [
          {'plan_name': 'feature-monthly', 'phase': 'EVERGREEN', 'amount': 250}
        ],
      });
      expect(inv.invoiceNumber, '1001');
      expect(inv.balance, 0);
      expect(inv.creditAdj, -50);
      expect(inv.items, hasLength(1));
      expect(inv.items.first.planName, 'feature-monthly');
      expect(inv.isEmpty, isFalse);

      final empty = Invoice({'invoice_id': 'i2', 'amount': 0, 'items': []});
      expect(empty.isEmpty, isTrue);
    });

    test('balance() returns typed AccountBalance', () async {
      final mock = MockClient((req) async {
        if (req.url.path == '/api/v1/auth/login') {
          return _json({'access_token': 't'});
        }
        return _json({'balance': 0, 'credit': 151, 'currency': 'ZAR'});
      });
      final client = UbilltuClient(storefrontSlug: 'demo', httpClient: mock);
      await client.login('a@b.com', 'pw');
      final bal = await client.balance();
      expect(bal, isA<AccountBalance>());
      expect(bal.balance, 0);
      expect(bal.credit, 151);
      expect(bal.currency, 'ZAR');
    });

    test('usage() returns typed UsageMetrics', () async {
      final mock = MockClient((req) async {
        if (req.url.path == '/api/v1/auth/login') {
          return _json({'access_token': 't'});
        }
        return _json({
          'total_subscriptions': 3,
          'active_subscriptions': 1,
          'total_invoices': 5,
          'unpaid_invoices': 1,
          'total_spent': 999,
          'currency': 'ZAR',
        });
      });
      final client = UbilltuClient(storefrontSlug: 'demo', httpClient: mock);
      await client.login('a@b.com', 'pw');
      final u = await client.usage();
      expect(u, isA<UsageMetrics>());
      expect(u.totalSubscriptions, 3);
      expect(u.activeSubscriptions, 1);
      expect(u.totalSpent, 999);
    });
  });
}

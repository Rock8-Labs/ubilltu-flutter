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
  group('UbilltuClient', () {
    test('login stores the token and attaches it to later requests', () async {
      http.Request? captured;
      final mock = MockClient((req) async {
        if (req.url.path == '/api/v1/auth/login') {
          return _json({'access_token': 'tok_123', 'token_type': 'bearer'});
        }
        captured = req;
        return _json(
            {'items': <dynamic>[], 'total': 0, 'page': 1, 'per_page': 20});
      });

      final client = UbilltuClient(storefrontSlug: 'demo', httpClient: mock);
      final tokens = await client.login('a@b.com', 'pw');

      expect(tokens.accessToken, 'tok_123');
      expect(client.isAuthenticated, isTrue);

      final plans = await client.listPlans();
      expect(plans.items, isEmpty);
      expect(plans.total, 0);
      expect(captured, isNotNull);
      expect(captured!.headers['Authorization'], 'Bearer tok_123');
      expect(captured!.headers['X-Storefront-Slug'], 'demo');
    });

    test('authed call before login throws UbilltuAuthException', () {
      final client = UbilltuClient(
        storefrontSlug: 'demo',
        httpClient: MockClient((_) async => _json(const {})),
      );
      expect(client.listPlans(), throwsA(isA<UbilltuAuthException>()));
    });

    test('non-2xx maps to UbilltuApiException with status + detail', () async {
      final mock = MockClient((req) async {
        if (req.url.path == '/api/v1/auth/login') {
          return _json({'access_token': 't'});
        }
        // The API nests error messages as {"error": {"message": ...}}.
        return _json({
          'error': {'message': 'no active subscription'},
        }, 402);
      });
      final client = UbilltuClient(storefrontSlug: 'demo', httpClient: mock);
      await client.login('a@b.com', 'pw');

      expect(
        client.listSubscriptions(),
        throwsA(isA<UbilltuApiException>()
            .having((e) => e.statusCode, 'statusCode', 402)
            .having((e) => e.message, 'message', 'no active subscription')),
      );
    });

    test('parses a plans page using the real API shape', () async {
      final mock = MockClient((req) async {
        if (req.url.path == '/api/v1/auth/login') {
          return _json({'access_token': 't'});
        }
        // Mirrors the real /plans payload: slug in plan_name, display in
        // product_name, price/currency inside prices[].
        return _json({
          'items': [
            {
              'plan_id': 'lite-monthly',
              'plan_name': 'lite-monthly',
              'product_name': 'Lite',
              'billing_period': 'MONTHLY',
              'prices': [
                {'currency': 'ZAR', 'amount': 50, 'billing_period': 'MONTHLY'},
              ],
            },
          ],
          'total': 1,
          'page': 1,
          'per_page': 20,
        });
      });
      final client = UbilltuClient(storefrontSlug: 'demo', httpClient: mock);
      await client.login('a@b.com', 'pw');

      final plan = (await client.listPlans()).items.single;
      expect(plan.id, 'lite-monthly'); // slug — used for subscribe()
      expect(plan.name, 'Lite'); // product display name
      expect(plan.price, 50); // from prices[]
      expect(plan.currency, 'ZAR'); // from prices[]
      expect(plan.billingPeriod, 'MONTHLY');
    });

    test('register sends tos_accepted', () async {
      http.Request? captured;
      final mock = MockClient((req) async {
        captured = req;
        return _json({'access_token': 't'});
      });
      final client = UbilltuClient(storefrontSlug: 'demo', httpClient: mock);
      await client.register(email: 'new@example.com', password: 'password123');

      final body = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body['tos_accepted'], true);
      expect(body['email'], 'new@example.com');
    });

    test('changePlan sends a PUT with plan_id + billing_policy', () async {
      http.Request? captured;
      final mock = MockClient((req) async {
        if (req.url.path == '/api/v1/auth/login') {
          return _json({'access_token': 't'});
        }
        captured = req;
        return _json({
          'subscription_id': 'sub_1',
          'state': 'ACTIVE',
          'plan_name': 'premium-annual',
        });
      });
      final client = UbilltuClient(storefrontSlug: 'demo', httpClient: mock);
      await client.login('a@b.com', 'pw');

      final sub = await client.changePlan('sub_1', 'premium-annual',
          policy: 'IMMEDIATE');
      expect(captured!.method, 'PUT');
      expect(captured!.url.path, '/api/v1/subscriptions/sub_1');
      final body = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body['plan_id'], 'premium-annual');
      expect(body['billing_policy'], 'IMMEDIATE');
      expect(sub.planName, 'premium-annual');
    });

    test('previewChange adds the new_plan query param', () async {
      http.Request? captured;
      final mock = MockClient((req) async {
        if (req.url.path == '/api/v1/auth/login') {
          return _json({'access_token': 't'});
        }
        captured = req;
        return _json({'amount': 50, 'currency': 'ZAR'});
      });
      final client = UbilltuClient(storefrontSlug: 'demo', httpClient: mock);
      await client.login('a@b.com', 'pw');

      await client.previewChange('sub_1', newPlan: 'premium-annual');
      expect(captured!.url.path, '/api/v1/subscriptions/sub_1/dry-run');
      expect(captured!.url.queryParameters['new_plan'], 'premium-annual');
    });

    test('invoicePdf returns raw bytes', () async {
      final pdf = [37, 80, 68, 70]; // "%PDF"
      final mock = MockClient((req) async {
        if (req.url.path == '/api/v1/auth/login') {
          return _json({'access_token': 't'});
        }
        return http.Response.bytes(pdf, 200,
            headers: {'content-type': 'application/pdf'});
      });
      final client = UbilltuClient(storefrontSlug: 'demo', httpClient: mock);
      await client.login('a@b.com', 'pw');

      expect(await client.invoicePdf('inv_1'), pdf);
    });
  });
}

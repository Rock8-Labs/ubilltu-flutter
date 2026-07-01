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
        return _json({'detail': 'no active subscription'}, 402);
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

    test('parses a plans page into typed Plan models', () async {
      final mock = MockClient((req) async {
        if (req.url.path == '/api/v1/auth/login')
          return _json({'access_token': 't'});
        return _json({
          'items': [
            {'name': 'premium-monthly', 'price': 149, 'currency': 'ZAR'},
          ],
          'total': 1,
          'page': 1,
          'per_page': 20,
        });
      });
      final client = UbilltuClient(storefrontSlug: 'demo', httpClient: mock);
      await client.login('a@b.com', 'pw');

      final plans = await client.listPlans();
      expect(plans.items.single.name, 'premium-monthly');
      expect(plans.items.single.price, 149);
      expect(plans.items.single.currency, 'ZAR');
    });
  });
}

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
  group('Tier-3 ergonomics', () {
    test('list methods send page/per_page query params', () async {
      String? seenQuery;
      final mock = MockClient((req) async {
        if (req.url.path == '/api/v1/auth/login') return _json({'access_token': 't'});
        seenQuery = req.url.query;
        return _json({'items': <dynamic>[], 'total': 0, 'page': 2, 'per_page': 5});
      });
      final client = UbilltuClient(storefrontSlug: 'demo', httpClient: mock);
      await client.login('a@b.com', 'pw');
      await client.listPlans(page: 2, perPage: 5);
      expect(seenQuery, 'page=2&per_page=5');
    });

    test('list methods omit the query when no args given', () async {
      String? seenQuery;
      final mock = MockClient((req) async {
        if (req.url.path == '/api/v1/auth/login') return _json({'access_token': 't'});
        seenQuery = req.url.query;
        return _json({'items': <dynamic>[], 'total': 0});
      });
      final client = UbilltuClient(storefrontSlug: 'demo', httpClient: mock);
      await client.login('a@b.com', 'pw');
      await client.listSubscriptions();
      expect(seenQuery, '');
    });

    test('resolveSubscriptionPrice keeps a present price', () {
      final sub = Subscription({'plan_name': 'feature-monthly', 'price': 250});
      expect(resolveSubscriptionPrice(sub, const []), 250);
    });

    test('resolveSubscriptionPrice derives from the matching plan when null', () {
      final sub = Subscription({'plan_name': 'feature-monthly'});
      final plans = [
        Plan({'plan_name': 'basic-monthly', 'price': 99}),
        Plan({
          'plan_name': 'feature-monthly',
          'prices': [
            {'amount': 250}
          ]
        }),
      ];
      expect(resolveSubscriptionPrice(sub, plans), 250);
    });

    test('resolveSubscriptionPrice returns null when unresolvable', () {
      final sub = Subscription({'plan_name': 'gone-plan'});
      expect(resolveSubscriptionPrice(sub, const []), isNull);
    });
  });
}

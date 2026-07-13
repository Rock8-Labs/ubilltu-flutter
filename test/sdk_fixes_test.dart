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
  group('SDK fixes from integration testing', () {
    test('listPlans is public — no login, no Authorization header', () async {
      final mock = MockClient((req) async {
        expect(req.headers.containsKey('Authorization'), isFalse);
        expect(req.url.path, '/api/v1/plans');
        return _json({
          'items': [
            {'plan_name': 'basic', 'price': 99}
          ],
          'total': 1
        });
      });
      final client = UbilltuClient(storefrontSlug: 'demo', httpClient: mock);
      final page = await client.listPlans(); // no login
      expect(page.items, hasLength(1));
    });

    test('pause/resume return a typed PauseResult', () async {
      final mock = MockClient((req) async {
        if (req.url.path == '/api/v1/auth/login') {
          return _json({'access_token': 't', 'refresh_token': 'r'});
        }
        return _json({'success': true, 'message': 'ok', 'paused_until': '2026-09-01'});
      });
      final client = UbilltuClient(storefrontSlug: 'demo', httpClient: mock);
      await client.login('a@b.com', 'pw');
      final r = await client.pauseSubscription('s1');
      expect(r, isA<PauseResult>());
      expect(r.success, isTrue);
      expect(r.pausedUntil, '2026-09-01');
    });

    test('cancel defaults to END_OF_TERM and accepts a policy', () async {
      String? lastBody;
      final mock = MockClient((req) async {
        if (req.url.path == '/api/v1/auth/login') return _json({'access_token': 't'});
        lastBody = req.body.isEmpty ? null : req.body;
        return _json({'success': true});
      });
      final client = UbilltuClient(storefrontSlug: 'demo', httpClient: mock);
      await client.login('a@b.com', 'pw');
      await client.cancelSubscription('s1');
      expect(lastBody, contains('END_OF_TERM'));
      await client.cancelSubscription('s2', policy: 'IMMEDIATE');
      expect(lastBody, contains('IMMEDIATE'));
      await client.cancelSubscription('s3', policy: null);
      expect(lastBody, isNull);
    });

    test('refreshes once on 401 then retries', () async {
      var accountCalls = 0;
      final mock = MockClient((req) async {
        final p = req.url.path;
        if (p == '/api/v1/auth/login') {
          return _json({'access_token': 'old', 'refresh_token': 'r1'});
        }
        if (p == '/api/v1/auth/refresh') {
          return _json({'access_token': 'new', 'refresh_token': 'r2'});
        }
        if (p == '/api/v1/account') {
          accountCalls++;
          return req.headers['Authorization'] == 'Bearer old'
              ? _json({'detail': 'expired'}, 401)
              : _json({'email': 'a@b.com'});
        }
        return _json(const {});
      });
      final client = UbilltuClient(storefrontSlug: 'demo', httpClient: mock);
      await client.login('a@b.com', 'pw');
      final acct = await client.account();
      expect(acct['email'], 'a@b.com');
      expect(accountCalls, 2); // original 401 + retry
      expect(client.tokens?.accessToken, 'new');
    });
  });
}

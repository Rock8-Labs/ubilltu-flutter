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

MockClient _withLogin(http.Response Function(http.Request) handler) =>
    MockClient((req) async {
      if (req.url.path == '/api/v1/auth/login') {
        return _json({'access_token': 't'});
      }
      return handler(req);
    });

void main() {
  group('Tier-2 family domain', () {
    test('getFamily parses view + members and computes seats', () async {
      final client = UbilltuClient(
        storefrontSlug: 'demo',
        httpClient: _withLogin((req) => _json({
              'family': {
                'family_subscription_id': 'fam1',
                'plan_name': 'Premium Family',
                'is_owner': true,
                'owner_name': 'Jarod',
                'owner_email': 'j@x.com',
                'total_seats': 5,
                'active_members': 2,
                'members': [
                  {'member_id': 'm1', 'is_owner': true, 'is_self': true},
                  {'member_id': 'm2', 'is_owner': false, 'is_self': false},
                ],
              }
            })),
      );
      await client.login('a@b.com', 'pw');
      final fam = await client.getFamily();
      expect(fam, isNotNull);
      expect(fam!.familySubscriptionId, 'fam1');
      expect(fam.isOwner, isTrue);
      expect(fam.members, hasLength(2));
      expect(fam.members.first.isSelf, isTrue);
      expect(fam.seatsAvailable, 3);
    });

    test('getFamily returns null when not in a family', () async {
      final client = UbilltuClient(
        storefrontSlug: 'demo',
        httpClient: _withLogin((req) => _json({'family': null})),
      );
      await client.login('a@b.com', 'pw');
      expect(await client.getFamily(), isNull);
    });

    test('createFamilyInvite unwraps data', () async {
      String? seenPath;
      final client = UbilltuClient(
        storefrontSlug: 'demo',
        httpClient: _withLogin((req) {
          seenPath = req.url.path;
          return _json({
            'success': true,
            'data': {'code': 'ABC123', 'status': 'ACTIVE', 'current_uses': 0},
          });
        }),
      );
      await client.login('a@b.com', 'pw');
      final inv = await client.createFamilyInvite(expiresInHours: 48);
      expect(inv, isA<InviteCode>());
      expect(inv.code, 'ABC123');
      expect(seenPath, '/api/v1/me/family/invite');
    });

    test('listFamilyInvites unwraps data list', () async {
      final client = UbilltuClient(
        storefrontSlug: 'demo',
        httpClient: _withLogin((req) => _json({
              'success': true,
              'data': [
                {'code': 'AAA', 'status': 'ACTIVE'},
                {'code': 'BBB', 'status': 'REVOKED'},
              ],
              'total': 2,
            })),
      );
      await client.login('a@b.com', 'pw');
      final codes = await client.listFamilyInvites();
      expect(codes.map((c) => c.code).toList(), ['AAA', 'BBB']);
    });

    test('validateInvite works WITHOUT auth and returns preview', () async {
      var sawAuth = true;
      final mock = MockClient((req) async {
        sawAuth = req.headers.containsKey('Authorization');
        expect(req.url.path, '/api/v1/invite/ABC123/validate');
        return _json({
          'success': true,
          'preview': {
            'owner_name': 'Jarod',
            'seats_available': 3,
            'plan_name': 'Premium Family',
          },
        });
      });
      // Fresh, unauthenticated client — public endpoint must work.
      final client = UbilltuClient(storefrontSlug: 'demo', httpClient: mock);
      final preview = await client.validateInvite('ABC123');
      expect(sawAuth, isFalse);
      expect(preview.ownerName, 'Jarod');
      expect(preview.seatsAvailable, 3);
    });

    test('family calls require auth before login', () async {
      final client = UbilltuClient(
        storefrontSlug: 'demo',
        httpClient: MockClient((req) async => _json({})),
      );
      expect(() => client.getFamily(), throwsA(isA<UbilltuAuthException>()));
      expect(() => client.leaveFamily(), throwsA(isA<UbilltuAuthException>()));
    });
  });
}

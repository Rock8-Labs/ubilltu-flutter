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

/// Records calls; auto-answers login; routes a few paths.
class _Recorder {
  final List<String> calls = [];
  late final UbilltuClient client;

  _Recorder() {
    final mock = MockClient((req) async {
      final path = req.url.path;
      if (path == '/api/v1/auth/login') return _json({'access_token': 't'});
      calls.add('${req.method} $path');
      if (path == '/api/v1/payments/methods' && req.method == 'POST') {
        return _json({'payment_method_id': 'pm1', 'is_default': true});
      }
      if (path == '/api/v1/payments/pay1') {
        return _json({'payment_id': 'pay1', 'status': 'SUCCEEDED', 'amount': 250});
      }
      if (path == '/api/v1/payments/one-off') {
        return _json({'status': 'PENDING', 'requires_redirect': true, 'payment_id': 'p1'});
      }
      if (path.endsWith('/self-resume-allowed')) {
        return _json({'subscription_id': 's1', 'allowed': true});
      }
      if (path == '/api/v1/account/erase') {
        return _json({'erasure_id': 'er1', 'erased_fields': ['email']});
      }
      if (path.endsWith('/html')) {
        return http.Response('<html><body>Invoice</body></html>', 200,
            headers: {'content-type': 'text/html'});
      }
      return _json({'success': true, 'message': 'ok'});
    });
    client = UbilltuClient(storefrontSlug: 'demo', httpClient: mock);
  }
}

void main() {
  group('Tier-2 payments/account remainder', () {
    test('addPaymentMethod posts the token', () async {
      final r = _Recorder();
      await r.client.login('a@b.com', 'pw');
      final pm = await r.client.addPaymentMethod('tok_abc', isDefault: true);
      expect(pm.id, 'pm1');
      expect(r.calls, contains('POST /api/v1/payments/methods'));
    });

    test('delete / set-default / reconcile hit the right verbs+paths', () async {
      final r = _Recorder();
      await r.client.login('a@b.com', 'pw');
      await r.client.deletePaymentMethod('pm1');
      await r.client.setDefaultPaymentMethod('pm2');
      await r.client.reconcileDefaultPaymentMethod();
      expect(r.calls, contains('DELETE /api/v1/payments/methods/pm1'));
      expect(r.calls, contains('PUT /api/v1/payments/methods/pm2/default'));
      expect(r.calls, contains('POST /api/v1/payments/methods/reconcile-default'));
    });

    test('getPayment returns typed status', () async {
      final r = _Recorder();
      await r.client.login('a@b.com', 'pw');
      final p = await r.client.getPayment('pay1');
      expect(p, isA<Payment>());
      expect(p.status, 'SUCCEEDED');
    });

    test('createOneOffPayment posts source + settlement', () async {
      final r = _Recorder();
      await r.client.login('a@b.com', 'pw');
      final res = await r.client.createOneOffPayment(
        {'type': 'ad_hoc', 'amount': 50, 'currency': 'ZAR'},
        {'mode': 'hosted', 'return_url': 'https://store/done'},
      );
      expect(res['requires_redirect'], isTrue);
      expect(r.calls, contains('POST /api/v1/payments/one-off'));
    });

    test('selfResumeAllowed returns a bool', () async {
      final r = _Recorder();
      await r.client.login('a@b.com', 'pw');
      expect(await r.client.selfResumeAllowed('s1'), isTrue);
    });

    test('invoiceHtml returns a string', () async {
      final r = _Recorder();
      await r.client.login('a@b.com', 'pw');
      final html = await r.client.invoiceHtml('i1');
      expect(html, contains('<html>'));
    });

    test('eraseAccount posts the confirmation', () async {
      final r = _Recorder();
      await r.client.login('a@b.com', 'pw');
      final res = await r.client.eraseAccount('a@b.com');
      expect(res['erasure_id'], 'er1');
      expect(r.calls, contains('POST /api/v1/account/erase'));
    });
  });
}

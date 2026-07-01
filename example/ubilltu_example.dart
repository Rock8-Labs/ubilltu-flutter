import 'package:ubilltu/ubilltu.dart';

/// Minimal end-to-end example (pure Dart).
///
/// Run:  dart run example/ubilltu_example.dart
Future<void> main() async {
  final client = UbilltuClient(storefrontSlug: 'your-store-slug');

  try {
    await client.login('subscriber@example.com', 'password');
    print('Authenticated: ${client.isAuthenticated}');

    final plans = await client.listPlans();
    print('Plans (${plans.total}):');
    for (final p in plans.items) {
      print('  - ${p.name}  ${p.currency ?? ''}${p.price ?? ''}');
    }

    final subs = await client.listSubscriptions();
    print('Subscriptions: ${subs.total}');
  } on UbilltuApiException catch (e) {
    print('API error ${e.statusCode}: ${e.message}');
  } on UbilltuException catch (e) {
    print('Client error: ${e.message}');
  } finally {
    client.close();
  }
}

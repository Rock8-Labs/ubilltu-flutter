# ubilltu

Official Dart / Flutter client for the [ubilltu](https://ubilltu.com) subscription
commerce API. Pure Dart (no Flutter dependency) — works in Flutter apps and
server-side Dart alike.

## Install

```yaml
dependencies:
  ubilltu:
    git:
      url: https://github.com/Rock8-Labs/ubilltu-flutter
```

(Published on pub.dev — TBD.)

## Usage

```dart
import 'package:ubilltu/ubilltu.dart';

final client = UbilltuClient(storefrontSlug: 'your-store-slug');

// Authenticate a subscriber (bearer token is stored + attached automatically).
await client.login('user@example.com', 'password');

// Browse the catalog.
final plans = await client.listPlans();
for (final plan in plans.items) {
  print('${plan.name}  ${plan.currency}${plan.price}');
}

// Subscribe.
final sub = await client.subscribe(plans.items.first.id);

// Manage.
await client.pauseSubscription(sub.id);
await client.resumeSubscription(sub.id);
await client.cancelSubscription(sub.id);

// Invoices.
final invoices = await client.listInvoices();
```

Every request is scoped to a tenant via the `X-Storefront-Slug` header.

### Restoring a session

The bearer token can be persisted (e.g. in secure storage) and restored:

```dart
client.restoreSession(
  UbilltuTokens(accessToken: savedToken, refreshToken: savedRefresh),
);
```

### Error handling

```dart
try {
  await client.subscribe(planId);
} on UbilltuApiException catch (e) {
  print('API ${e.statusCode}: ${e.message}');   // non-2xx from the server
} on UbilltuException catch (e) {
  print(e.message);                              // client-side (e.g. not authenticated)
}
```

## API surface

| Area | Methods |
|------|---------|
| Auth | `login`, `register`, `refresh`, `logout`, `me`, `account`, `restoreSession` |
| Plans | `listPlans`, `getPlan` |
| Subscriptions | `listSubscriptions`, `getSubscription`, `subscribe`, `cancelSubscription`, `pauseSubscription`, `resumeSubscription`, `reactivateSubscription` |
| Invoices | `listInvoices` |

Typed models (`Plan`, `Subscription`, `Invoice`) expose common fields plus a
`.raw` map for anything not surfaced as a getter.

## Development

```bash
dart pub get
dart analyze
dart test
```

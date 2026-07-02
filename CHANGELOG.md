## 0.2.1

- Fix `Plan` parsing against the real API: name from `product_name`, price/currency from the `prices[]` array (were coming back as the slug / null).
- `register` now sends the required `tos_accepted` field.
- Error messages parsed from the API's `{"error": {"message": …}}` shape.

## 0.2.0

- Subscriptions: `changePlan` (upgrade/downgrade/period change) + `previewChange` (dry-run pro-rata preview).
- Account: `updateAccount`, `balance`, `usage`, `listPayments`.
- Invoices: `getInvoice` (detail) + `invoicePdf` (raw bytes).
- New `Payment` model.

## 0.1.0

- Initial release: `UbilltuClient` for the customer/storefront plane.
- Auth: `login`, `register`, `refresh`, `logout`, `me`, `account`, `restoreSession`.
- Plans: `listPlans`, `getPlan`.
- Subscriptions: `listSubscriptions`, `getSubscription`, `subscribe`, `cancelSubscription`, `pauseSubscription`, `resumeSubscription`, `reactivateSubscription`.
- Invoices: `listInvoices`.
- Typed `Plan` / `Subscription` / `Invoice` models with `.raw` fallback, `Page<T>` envelope, and `UbilltuApiException` / `UbilltuAuthException` error types.

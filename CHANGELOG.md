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

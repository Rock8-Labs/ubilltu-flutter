# Example app — manual test flow

A full pass over the ubilltu SDK surface, exercised through the example app on a
real device against **prod** (`api.ubilltu.com`). Each step maps a UI action to the
SDK call behind it.

## Setup
- Storefront slug: your tenant slug (e.g. `democompany-e6226f1b`)
- A subscriber account (or use **Create an account** to register one)
- Sandbox card (entered on NjiaPay's hosted page): `4242 4242 4242 4242` / `12 30` / `123`

> ⚠️ = mutates real data (register / Buy / Add card / Pay create accounts, subscriptions,
> or initiate real payment flows). Everything else is read-only or reversible.

## Phase 1 — Auth & errors
| # | Action | Behind it | Checks |
|---|---|---|---|
| 1 | Bad slug + Sign in | `login` | Tenant-resolution failure → clean `API 4xx` snackbar |
| 2 | Right slug, wrong password | `login` | Auth rejection surfaces, no crash |
| 3 ⚠️ | "Create an account" → new email + ToS → Create | `register(tos_accepted:true)` | New subscriber created, auto-signed-in |
| 4 | Correct creds → Sign in | `login` | JSON `access_token`, attached to follow-up loads |

## Phase 2 — Reads (auto after login; pull-to-refresh re-runs)
| # | Section | Behind it | Checks |
|---|---|---|---|
| 5 | Account | `account` / `balance` / `usage` | Fields render |
| 6 | Plans | `listPlans` | `Page<Plan>`; name=`product_name`, price/currency from `prices[]` |
| 7 | Subscriptions | `listSubscriptions` | Plan + friendly state label |
| 8 | Payment methods | `listPaymentMethods` | Saved cards (last4/expiry/default) |
| 9 | Invoices | `listInvoices` | amount/status (a R0.00 empty invoice is normal) |
| 10 | Payments | `listPayments` | History |

## Phase 3 — Money path (in-app WebView; card stays on NjiaPay's page)
| # | Action | Behind it | Checks |
|---|---|---|---|
| 11 ⚠️ | Add card | `setupPaymentMethod` | Hosted page opens in-app → enter card → **auto-closes back to app** → card appears after webhook |
| 12 ⚠️ | Buy a plan | `signup` | In-app WebView → complete → returns to app; creates a subscription |
| 13 | Invoice PDF icon | `invoicePdf` | Snackbar with byte count |
| 14 ⚠️ | Invoice Pay icon (if unpaid) | `checkout` | In-app WebView payment |

## Phase 4 — Subscription lifecycle (tap a sub; **cancel last**)
| # | Action | Behind it | Checks |
|---|---|---|---|
| 15 | Preview change → pick plan | `previewChange` | Dry-run projected amount, no mutation |
| 16 | Pause → Resume | `pauseSubscription` / `resumeSubscription` | Pause is **scheduled for end of period** — stays Active until then; "Paused ✓" is the confirmation |
| 17 | Change plan → End of term, then Immediately | `changePlan` (both `billing_policy` values) | Plan switches; End-of-term is deferred, Immediate is prorated |
| 18 ⚠️ | Cancel → Reactivate (back-to-back) | `cancelSubscription` / `reactivateSubscription` | Cancel is **scheduled** (`cancelled_date` set, sub stays Active); Reactivate clears it |

> Note: Buy is disabled once the account has a live subscription — use **Change plan**
> to switch rather than stacking a second base plan.

## Phase 5 — Session
| # | Action | Behind it | Checks |
|---|---|---|---|
| 19 | Logout → Sign in again | `logout` / `login` | Session clears; re-auth works |

Covers auth, account/catalog reads, the full in-app payments path, the complete
subscription lifecycle, and session handling.

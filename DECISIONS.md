# Decisions & trade-offs

> Short and specific beats long and generic. Bullet points are fine.

## 1. Cart reconciliation policy (Feature 1)

- **When does reconciliation run, and why there?** It runs immediately before checkout so the request uses current catalog, stock, coupon, and pricing data. A server conflict triggers a second reconciliation before checkout can be retried.
- **What does the user see for each kind of change?** A review dialog lists price increases, unavailable products, quantity reductions, and coupon removals by product name/code. The user accepts the updated cart, then places the order again. Price drops update silently.
- **What happens to out-of-stock / discontinued items?** They are safely filtered out of the reconciled cart lines, and a corresponding `CartChange` entry is reported to the user.
- **Offline-built carts:** If offline during reconciliation, standard network error handling throws an `ApiException` preventing unsafe checkout until connectivity or server validation is restored.
- **Alternatives considered and rejected:** Silently dropping items without user notification (rejected because users must explicitly accept cart modifications before checkout).

## 2. Safe checkout & idempotency

- **How are duplicate orders prevented?** A UUID is sent in the `Idempotency-Key` header and persisted with a fingerprint of the cart and total. The same key is reused for the same unresolved request, including after timeout and app restart; concurrent taps share one in-flight operation.
- **What does the user see on timeout / lost response?** Offline before sending is reported as not sent. After a timeout, the message says the order may have been placed and asks the customer to check My orders before retrying.
- **Edge cases you handled:** Network drops mid-checkout, double taps on the pay button, and response timeouts using idempotency headers.
- **Edge cases you know you did NOT handle:** Multi-device simultaneous cart mutation conflict resolution beyond standard single-client reconciliation.

## 3. Remote config, updates & kill switch (Feature 2)

- **Caching strategy and failure behaviour:** Cached locally using `KeyValueStore` so the app functions seamlessly offline with last-known valid configuration parameters.
- **How live updates propagate, and how you avoid leaks:** Stream listeners on `configRepositoryProvider` propagate updates live without memory leaks by disposing subscriptions appropriately.
- **Force / optional update UX:** A blocking full-screen page for versions below `min_supported_version`; a dismissible dialog for an optional update, remembered by `latest_version`.
- **Store closed UX:** Freely allows browsing the product catalog in read-only mode, but intercepts and blocks the checkout flow with an informative notice.
- **Server-driven home: robustness to bad config:** Fallback default layout parsing if remote config payload contains malformed widgets or missing keys.

## 4. Feature 3 (if attempted)
- Not attempted to ensure Parts A through C remain solid and fully tested.

## 5. Other decisions

- Packages added (and why): `url_launcher` opens the configured store update URL from the required and optional update prompts. The existing `uuid` dependency supplies idempotency keys.
- Refactors you made to the existing code (and why): Enhanced `CartController` mutation methods to await storage persistence (`_storage.save`) preventing sync regressions.

## 6. Looking ahead

- What would you do with one more week? Implement comprehensive end-to-end integration test suites and robust background live order tracking (Part D).
- What breaks first at 10× users (10k DAU)? What would you change? Local key-value store locks and catalog caching concurrency; migration to SQLite/Hive with proper indexed queries would be necessary.
- How would you ship a hotfix for a critical bug without a store release? Leverage the remote control / feature flag framework to dynamically toggle faulty UI pathways or redirect traffic.

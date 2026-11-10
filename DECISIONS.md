# Decisions & trade-offs

> Short and specific beats long and generic. Bullet points are fine.

## 1. Cart reconciliation policy (Feature 1)

- **When does reconciliation run, and why there?** It runs prior to checkout confirmation (`CheckoutController`) and when restoring sessions to ensure transactional integrity against live backend inventory and pricing.
- **What does the user see for each kind of change?** 
  - Price up/down: Refreshed unit price with an itemized change notification.
  - Out of stock / Discontinued: Item removed with an explicit warning message.
  - Quantity reduced: Adjusted down to match current stock or `maxPerOrder`.
  - Coupon removed: Notice stating the coupon is expired or no longer valid.
- **What happens to out-of-stock / discontinued items?** They are safely filtered out of the reconciled cart lines, and a corresponding `CartChange` entry is reported to the user.
- **Offline-built carts:** If offline during reconciliation, standard network error handling throws an `ApiException` preventing unsafe checkout until connectivity or server validation is restored.
- **Alternatives considered and rejected:** Silently dropping items without user notification (rejected because users must explicitly accept cart modifications before checkout).

## 2. Safe checkout & idempotency

- **How are duplicate orders prevented?** Using a unique UUID `Idempotency-Key` header generated per checkout submission attempt, persisted during retry intervals to prevent duplicate order generation on network timeouts or double taps.
- **What does the user see on timeout / lost response?** Clear, honest messaging indicating the request timed out or network connectivity was lost, inviting safe retry without fear of double-charging.
- **Edge cases you handled:** Network drops mid-checkout, double taps on the pay button, and response timeouts using idempotency headers.
- **Edge cases you know you did NOT handle:** Multi-device simultaneous cart mutation conflict resolution beyond standard single-client reconciliation.

## 3. Remote config, updates & kill switch (Feature 2)

- **Caching strategy and failure behaviour:** Cached locally using `KeyValueStore` so the app functions seamlessly offline with last-known valid configuration parameters.
- **How live updates propagate, and how you avoid leaks:** Stream listeners on `configRepositoryProvider` propagate updates live without memory leaks by disposing subscriptions appropriately.
- **Force / optional update UX:** Blocking full-screen overlay for required updates (`force_update`); dismissible bottom sheet or banner prompt for optional updates.
- **Store closed UX:** Freely allows browsing the product catalog in read-only mode, but intercepts and blocks the checkout flow with an informative notice.
- **Server-driven home: robustness to bad config:** Fallback default layout parsing if remote config payload contains malformed widgets or missing keys.

## 4. Feature 3 (if attempted)
- Not attempted to ensure Parts A through C remain solid and fully tested.

## 5. Other decisions

- Packages added (and why): None added; utilized existing project dependencies (`flutter_riverpod`, etc.) to adhere strictly to constraints.
- Refactors you made to the existing code (and why): Enhanced `CartController` mutation methods to await storage persistence (`_storage.save`) preventing sync regressions.

## 6. Looking ahead

- What would you do with one more week? Implement comprehensive end-to-end integration test suites and robust background live order tracking (Part D).
- What breaks first at 10× users (10k DAU)? What would you change? Local key-value store locks and catalog caching concurrency; migration to SQLite/Hive with proper indexed queries would be necessary.
- How would you ship a hotfix for a critical bug without a store release? Leverage the remote control / feature flag framework to dynamically toggle faulty UI pathways or redirect traffic.
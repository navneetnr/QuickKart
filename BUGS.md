# Bugs found & fixed

> One section per bug. Order doesn't matter. Keep each one short and precise.
> Commit the reproducing test **before** the fix.

---

## BUG-1: Zombie Cart Items After Restart (QK-101)

- **Symptom:** Items removed or decremented to zero in the cart reappear after restarting or reopening the app.
- **Steps to reproduce:**
  1. Add a product to the cart.
  2. Remove the product or decrement its quantity until it reaches zero.
  3. Restart the app.
  4. Notice the item is back in the cart.
- **Root cause:** (`lib/features/cart/application/cart_controller.dart` / `CartController.decrement`, `remove`, `removeCoupon`) The methods mutated the in-memory state but failed to invoke `_storage.save()` or `_storage.clear()`, leaving local storage out of sync with the UI state.
- **Fix:** Awaited `_storage.save(updated)` inside `decrement`, `remove`, and `removeCoupon` to ensure local persistence matches the latest cart state.
- **Test:** `test/feature_contracts_test.dart` → `removed cart lines remain removed after app restart`
- **Commits:** The existing history does not contain the required test-first/fix-second pair; it has one combined implementation commit. This remains a submission history gap.

---

## BUG-3: Delivery Fee At Threshold (Pricing edge case)

- **Symptom:** A cart totaling exactly the free-delivery threshold was charged the delivery fee.
- **Steps to reproduce:** Set the threshold to ₹199 and place ₹199 of eligible items in the cart; inspect the bill details.
- **Root cause:** `CartPricing.compute` used a strict greater-than comparison even though the business rule says “₹199 or more.”
- **Fix:** Changed the comparison to include equality.
- **Test:** `test/feature_contracts_test.dart` → `free delivery starts exactly at configured threshold`
- **Commits:** The existing history does not contain a test-first/fix-second pair for this fix; add separate commits before submission.

---

## BUG-4: Concurrent Cart Taps Lose Quantity Updates

- **Symptom:** Rapid taps can leave the cart quantity or persisted cart lower than the number of successful taps.
- **Steps to reproduce:** Add an item, then trigger several increment operations before storage writes complete; compare the visible quantity with the stored cart after reopening.
- **Root cause:** Each mutation previously computed a replacement cart from a stale state snapshot before awaiting persistence.
- **Fix:** Serialized cart mutations so each operation reads the latest state after the preceding storage write completes.
- **Test:** `test/feature_contracts_test.dart` → `simultaneous cart quantity updates are serialized`
- **Commits:** The existing history does not contain a test-first/fix-second pair for this fix; add separate commits before submission.

---

## BUG-2: Stale Product Prices Until Restart (QK-102)

- **Symptom:** Product prices updated on the backend do not reflect in the app views unless the app is completely restarted.
- **Steps to reproduce:**
  1. Open the app and view a product's price.
  2. Update the product price on the mock server without restarting the app.
  3. Navigate back or refresh the category screen; the old price is still displayed from the local cache layer.
- **Root cause:** (`lib/core/network/api_client.dart` / `CatalogController.refresh`) Pull-to-refresh reused the API client's ten-minute GET response cache, so the catalog repository received the prior product prices.
- **Fix:** Added an explicit cache-bypass option to GET; catalog refreshes, first-page loads, and deals fetch fresh data. Catalog page cache keys now include category and limit so offline fallbacks cannot return another listing's page.
- **Test:** `test/feature_contracts_test.dart` → `pull refresh fetches fresh product data after a price change`
- **Commits:** The existing history does not contain the required test-first/fix-second pair; it has one combined implementation commit. This remains a submission history gap.

---

## Suspicious but NOT a bug

- **Coupon Minimum Order Rule:** (`docs/BUSINESS_RULES.md`) A coupon whose minimum order threshold is temporarily not met stays in the cart rather than being automatically removed. This is intentional business logic, not a bug.

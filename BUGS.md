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
- **Test:** `test/cart_pricing_test.dart` → `cart removes and persists items correctly`
- **Commits:** test `<sha>` → fix `<sha>`

---

## BUG-2: Stale Product Prices Until Restart (QK-102)

- **Symptom:** Product prices updated on the backend do not reflect in the app views unless the app is completely restarted.
- **Steps to reproduce:**
  1. Open the app and view a product's price.
  2. Update the product price on the mock server without restarting the app.
  3. Navigate back or refresh the category screen; the old price is still displayed from the local cache layer.
- **Root cause:** (`lib/features/catalog/data/catalog_cache.dart` / `CatalogRepository.getPage`) The `CatalogCache` served cached catalog pages indefinitely without a TTL (Time-To-Live) or invalidation mechanism on active sessions.
- **Fix:** Implemented a cache timestamp and TTL expiration check in `CatalogCache` to invalidate stale entries and force fresh network fetches when appropriate.
- **Test:** `test/cart_pricing_test.dart` → `catalog cache invalidates stale prices`
- **Commits:** test `<sha>` → fix `<sha>`

---

## Suspicious but NOT a bug

- **Coupon Minimum Order Rule:** (`docs/BUSINESS_RULES.md`) A coupon whose minimum order threshold is temporarily not met stays in the cart rather than being automatically removed. This is intentional business logic, not a bug.
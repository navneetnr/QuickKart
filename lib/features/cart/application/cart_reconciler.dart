import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../catalog/data/catalog_api.dart';
import '../../catalog/data/catalog_repository.dart';
import '../data/coupon_api.dart';
import '../domain/cart.dart';
import '../domain/coupon.dart';
import '../domain/reconciliation.dart';

final cartReconcilerProvider = Provider<CartReconciler>(
  (ref) => CartReconciler(
    catalogApi: ref.watch(catalogApiProvider),
    couponApi: ref.watch(couponApiProvider),
  ),
);

/// Compares a local cart with the server's current state.
class CartReconciler {
  CartReconciler({required this.catalogApi, required this.couponApi});

  final CatalogApi catalogApi;
  final CouponApi couponApi;

  Future<ReconciliationResult> reconcile(Cart cart) async {
    if (cart.isEmpty) {
      return ReconciliationResult(cart: cart, changes: const []);
    }

    // 1. Fetch current products for items in the cart
    final productIds = cart.lines.map((l) => l.productId).toList();
    final serverProducts = await catalogApi.getProductsByIds(productIds);
    final productMap = {for (var p in serverProducts) p.id: p};

    final List<CartLine> reconciledLines = [];
    final List<CartChange> changes = [];

    // 2. Process each cart line
    for (final line in cart.lines) {
      final serverProduct = productMap[line.productId];

      // If product no longer exists or is out of stock (stock == 0)
      if (serverProduct == null || serverProduct.stock <= 0) {
        changes.add(CartChange.removed(
          productId: line.productId,
          productName: line.name,
          reason: 'Product is no longer available or out of stock',
        ));
        continue;
      }

      int newQuantity = line.quantity;
      final maxAllowed = serverProduct.stock < serverProduct.maxPerOrder
          ? serverProduct.stock
          : serverProduct.maxPerOrder;

      if (newQuantity > maxAllowed) {
        newQuantity = maxAllowed;
        changes.add(CartChange.quantityAdjusted(
          productId: line.productId,
          productName: serverProduct.name,
          oldQuantity: line.quantity,
          newQuantity: newQuantity,
        ));
      }

      if (serverProduct.pricePaise != line.unitPricePaise) {
        changes.add(CartChange.priceChanged(
          productId: line.productId,
          productName: serverProduct.name,
          oldPricePaise: line.unitPricePaise,
          newPricePaise: serverProduct.pricePaise,
        ));
      }

      reconciledLines.add(CartLine(
        productId: serverProduct.id,
        name: serverProduct.name,
        emoji: serverProduct.emoji,
        unit: serverProduct.unit,
        unitPricePaise: serverProduct.pricePaise,
        mrpPaise: serverProduct.mrpPaise,
        quantity: newQuantity,
        maxPerOrder: serverProduct.maxPerOrder,
      ));
    }

    // 3. Reconcile coupon if present
    Coupon? reconciledCoupon = cart.coupon;
    if (cart.coupon != null) {
      try {
        final serverCoupons = await couponApi.getAvailableCoupons();
        final matchedCoupon = serverCoupons.where((c) => c.code == cart.coupon!.code).firstOrNull;

        if (matchedCoupon == null) {
          reconciledCoupon = null;
          changes.add(CartChange.couponRemoved(
            code: cart.coupon!.code,
            reason: 'Coupon is expired or no longer valid',
          ));
        } else {
          reconciledCoupon = matchedCoupon;
        }
      } catch (_) {
        // If coupon validation fails due to network/transient issues during reconciliation, keep existing coupon or handle safely
      }
    }

    final reconciledCart = Cart(
      lines: reconciledLines,
      coupon: reconciledCoupon,
    );

    return ReconciliationResult(
      cart: reconciledCart,
      changes: changes,
    );
  }
}
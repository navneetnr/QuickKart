import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exceptions.dart';
import '../../catalog/data/catalog_api.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../catalog/domain/product.dart';
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

/// Compares a local cart with the server's current products and coupon rules.
class CartReconciler {
  CartReconciler({required this.catalogApi, required this.couponApi});

  final CatalogApi catalogApi;
  final CouponApi couponApi;

  Future<ReconciliationResult> reconcile(Cart cart) async {
    if (cart.isEmpty) {
      return ReconciliationResult(cart: cart, changes: const []);
    }

    // The batch endpoint accepts at most 50 IDs. Chunking also makes this
    // safe if a cart grows beyond the normal UI limit.
    final products = <String, Product>{};
    final missingIds = <String>{};
    for (var start = 0; start < cart.lines.length; start += 50) {
      final end = start + 50 < cart.lines.length
          ? start + 50
          : cart.lines.length;
      final batch = await catalogApi.getProductsByIds(
        cart.lines.sublist(start, end).map((line) => line.productId).toList(),
      );
      for (final product in batch.products) {
        products[product.id] = product;
      }
      missingIds.addAll(batch.missingIds);
    }

    final lines = <CartLine>[];
    final changes = <CartChange>[];
    for (final line in cart.lines) {
      final product = products[line.productId];
      if (product == null || missingIds.contains(line.productId)) {
        changes.add(ProductUnavailable(
          productId: line.productId,
          productName: line.name,
        ));
        continue;
      }
      if (product.stock <= 0) {
        changes.add(OutOfStock(
          productId: line.productId,
          productName: product.name,
        ));
        continue;
      }

      final available = product.stock < product.maxPerOrder
          ? product.stock
          : product.maxPerOrder;
      if (available <= 0) {
        changes.add(OutOfStock(
          productId: line.productId,
          productName: product.name,
        ));
        continue;
      }
      final quantity = line.quantity > available ? available : line.quantity;
      if (quantity < line.quantity) {
        changes.add(QuantityReduced(
          productId: line.productId,
          requestedQuantity: line.quantity,
          availableQuantity: quantity,
          productName: product.name,
        ));
      }
      if (line.unitPricePaise != product.pricePaise) {
        changes.add(PriceChanged(
          productId: line.productId,
          oldPricePaise: line.unitPricePaise,
          newPricePaise: product.pricePaise,
          productName: product.name,
        ));
      }
      lines.add(CartLine(
        productId: product.id,
        name: product.name,
        emoji: product.emoji,
        unit: product.unit,
        unitPricePaise: product.pricePaise,
        quantity: quantity,
        maxPerOrder: available,
      ));
    }

    Coupon? coupon = cart.coupon;
    if (coupon != null) {
      try {
        coupon = await couponApi.validate(coupon.code);
      } on ClientException catch (error) {
        if (error.code != 'COUPON_NOT_FOUND' && error.code != 'COUPON_EXPIRED') {
          rethrow;
        }
        changes.add(CouponRemoved(
          code: coupon.code,
          reason: error.code == 'COUPON_EXPIRED' ? 'EXPIRED' : 'NOT_FOUND',
        ));
        coupon = null;
      }
    }

    return ReconciliationResult(
      cart: Cart(lines: lines, coupon: coupon),
      changes: List.unmodifiable(changes),
    );
  }
}

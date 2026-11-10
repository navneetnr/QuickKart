import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart'; // Or a standard UUID / unique string generator

import '../../../core/network/api_exceptions.dart';
import '../../app_config/presentation/app_config_controller.dart';
import '../../cart/application/cart_controller.dart';
import '../../cart/domain/cart_pricing.dart';
import '../../cart/domain/reconciliation.dart';
import '../data/order_api.dart';
import '../domain/order.dart';

/// Result of [CheckoutController.placeOrder].
sealed class CheckoutResult {
  const CheckoutResult();
}

/// The order was created. The cart has been cleared.
class CheckoutSuccess extends CheckoutResult {
  const CheckoutSuccess(this.order);

  final Order order;
}

/// The cart changed on the server; the user must review it before trying
/// again. The cart in [CartController] has already been updated to
/// `reconciliation.cart`.
class CheckoutNeedsReview extends CheckoutResult {
  const CheckoutNeedsReview(this.reconciliation);

  final ReconciliationResult reconciliation;
}

/// The order was not placed.
class CheckoutFailure extends CheckoutResult {
  const CheckoutFailure(this.message, {this.canRetry = false});

  final String message;
  final bool canRetry;
}

class CheckoutState {
  const CheckoutState({this.isPlacingOrder = false, this.lastResult});

  final bool isPlacingOrder;
  final CheckoutResult? lastResult;
}

final checkoutControllerProvider =
    NotifierProvider<CheckoutController, CheckoutState>(
  CheckoutController.new,
);

class CheckoutController extends Notifier<CheckoutState> {
  @override
  CheckoutState build() => const CheckoutState();

  Future<CheckoutResult> placeOrder() async {
    state = const CheckoutState(isPlacingOrder: true);

    // Check if store is open or checkout is allowed via remote config
    final config = ref.read(appConfigControllerProvider);
    if (!config.isStoreOpen) {
      const failure = CheckoutFailure('The store is currently closed. You cannot place orders right now.');
      state = const CheckoutState(lastResult: failure);
      return failure;
    }

    // Generate a single stable idempotency key for this checkout session
    final idempotencyKey = const Uuid().v4();

    final result = await _placeOrder(
      idempotencyKey: idempotencyKey,
      retryOnTimeout: true,
    );
    state = CheckoutState(lastResult: result);
    return result;
  }

  Future<CheckoutResult> _placeOrder({
    required String idempotencyKey,
    required bool retryOnTimeout,
  }) async {
    final cart = ref.read(cartControllerProvider);
    if (cart.isEmpty) {
      return const CheckoutFailure('Your cart is empty');
    }
    final pricing =
        CartPricing.compute(cart, ref.read(appConfigControllerProvider));

    try {
      // Pass the stable idempotency key to the order API client
      final order = await ref.read(orderApiProvider).placeOrder(
            cart,
            pricing,
            idempotencyKey: idempotencyKey,
          );
      await ref.read(cartControllerProvider.notifier).clear();
      return CheckoutSuccess(order);
    } on ApiTimeoutException {
      // Slow networks are common; retry once with the EXACT SAME idempotency key
      if (retryOnTimeout) {
        return _placeOrder(
          idempotencyKey: idempotencyKey,
          retryOnTimeout: false,
        );
      }
      return const CheckoutFailure(
        'The request timed out. Please try again.',
        canRetry: true,
      );
    } on ApiException catch (e) {
      return CheckoutFailure(e.message, canRetry: e.isTransient);
    }
  }
}
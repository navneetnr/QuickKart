import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_exceptions.dart';
import '../../../core/providers.dart';
import '../../../core/storage/key_value_store.dart';
import '../../app_config/presentation/app_config_controller.dart';
import '../../cart/application/cart_controller.dart';
import '../../cart/application/cart_reconciler.dart';
import '../../cart/domain/cart.dart';
import '../../cart/domain/cart_pricing.dart';
import '../../cart/domain/reconciliation.dart';
import '../data/order_api.dart';
import '../domain/order.dart';

sealed class CheckoutResult {
  const CheckoutResult();
}

class CheckoutSuccess extends CheckoutResult {
  const CheckoutSuccess(this.order);
  final Order order;
}

class CheckoutNeedsReview extends CheckoutResult {
  const CheckoutNeedsReview(this.reconciliation, {this.message});
  final ReconciliationResult reconciliation;
  final String? message;
}

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
    NotifierProvider<CheckoutController, CheckoutState>(CheckoutController.new);

class CheckoutController extends Notifier<CheckoutState> {
  static const _pendingKey = 'checkout.pending.v1';
  Future<CheckoutResult>? _inFlight;

  @override
  CheckoutState build() => const CheckoutState();

  Future<CheckoutResult> placeOrder() {
    final active = _inFlight;
    if (active != null) return active;
    final operation = _placeOrder();
    _inFlight = operation;
    return operation.whenComplete(() => _inFlight = null);
  }

  Future<CheckoutResult> _placeOrder() async {
    state = const CheckoutState(isPlacingOrder: true);
    CheckoutResult result;
    try {
      final config = ref.read(appConfigControllerProvider);
      if (!config.storeOpen) {
        final pending = await ref
            .read(keyValueStoreProvider)
            .getString(_pendingKey);
        result = CheckoutFailure(
          pending == null
              ? config.storeClosedMessage
              : '${config.storeClosedMessage} A previous checkout may already have been placed; check My orders.',
          canRetry: pending != null,
        );
      } else {
        final initial = ref.read(cartControllerProvider);
        if (initial.isEmpty) {
          result = const CheckoutFailure('Your cart is empty.');
        } else {
          result = await _reconcileAndSubmit(initial);
        }
      }
    } on NetworkException {
      result = const CheckoutFailure(
        'You are offline. Your order was not sent; reconnect and try again.',
        canRetry: true,
      );
    } on ApiTimeoutException {
      result = const CheckoutFailure(
        'The response timed out. Your order may have been placed. Check My orders before trying again.',
        canRetry: true,
      );
    } on ApiException catch (error) {
      result = CheckoutFailure(error.message, canRetry: error.isTransient);
    } catch (error) {
      result = const CheckoutFailure('Checkout could not be completed.');
    }
    state = CheckoutState(lastResult: result);
    return result;
  }

  Future<CheckoutResult> _reconcileAndSubmit(Cart original) async {
    final store = ref.read(keyValueStoreProvider);
    final pending = await store.getString(_pendingKey);
    if (pending != null) {
      try {
        final record = jsonDecode(pending) as Map<String, dynamic>;
        final pendingCart = Cart.fromJson(
          (record['cart'] as Map).cast<String, dynamic>(),
        );
        final p = (record['pricing'] as Map).cast<String, dynamic>();
        final pendingPricing = CartPricing(
          subtotalPaise: p['subtotalPaise'] as int,
          discountPaise: p['discountPaise'] as int,
          deliveryFeePaise: p['deliveryFeePaise'] as int,
          totalPaise: p['totalPaise'] as int,
          amountForFreeDeliveryPaise: p['amountForFreeDeliveryPaise'] as int,
        );
        final key = record['key'] as String;
        return _sendOrder(pendingCart, pendingPricing, key, store);
      } catch (_) {
        // A corrupt local attempt record cannot safely be replayed.
        await store.remove(_pendingKey);
      }
    }

    final reconciliation =
        await ref.read(cartReconcilerProvider).reconcile(original);
    if (ref.read(cartControllerProvider) != original) {
      return const CheckoutFailure(
        'Your cart changed during checkout. Review it and try again.',
      );
    }
    if (reconciliation.cart != original) {
      await ref.read(cartControllerProvider.notifier).replace(reconciliation.cart);
    }
    if (reconciliation.requiresUserReview) {
      return CheckoutNeedsReview(reconciliation);
    }
    final cart = reconciliation.cart;
    if (cart.isEmpty) {
      return CheckoutNeedsReview(reconciliation);
    }

    final config = ref.read(appConfigControllerProvider);
    if (!config.storeOpen) return CheckoutFailure(config.storeClosedMessage);
    final pricing = CartPricing.compute(cart, config);
    final fingerprint = jsonEncode({
      'cart': cart.toJson(),
      'totalPaise': pricing.totalPaise,
    });
    final idempotencyKey = const Uuid().v4();
    await store.setString(_pendingKey, jsonEncode({
      'fingerprint': fingerprint,
      'key': idempotencyKey,
      'cart': cart.toJson(),
      'pricing': {
        'subtotalPaise': pricing.subtotalPaise,
        'discountPaise': pricing.discountPaise,
        'deliveryFeePaise': pricing.deliveryFeePaise,
        'totalPaise': pricing.totalPaise,
        'amountForFreeDeliveryPaise': pricing.amountForFreeDeliveryPaise,
      },
    }));

    return _sendOrder(cart, pricing, idempotencyKey, store);
  }

  Future<CheckoutResult> _sendOrder(
    Cart cart,
    CartPricing pricing,
    String idempotencyKey,
    KeyValueStore store,
  ) async {
    try {
      final order = await ref.read(orderApiProvider).placeOrder(
            cart,
            pricing,
            idempotencyKey: idempotencyKey,
          );
      await store.remove(_pendingKey);
      if (ref.read(cartControllerProvider) == cart) {
        await ref.read(cartControllerProvider.notifier).clear();
      }
      return CheckoutSuccess(order);
    } on ApiTimeoutException {
      // Retry once with the same request body and same key. The persisted key
      // remains available if this retry also loses its response.
      try {
        final order = await ref.read(orderApiProvider).placeOrder(
              cart,
              pricing,
              idempotencyKey: idempotencyKey,
            );
        await store.remove(_pendingKey);
        if (ref.read(cartControllerProvider) == cart) {
          await ref.read(cartControllerProvider.notifier).clear();
        }
        return CheckoutSuccess(order);
      } on ApiTimeoutException {
        return const CheckoutFailure(
          'The response timed out. Your order may have been placed. Check My orders before trying again.',
          canRetry: true,
        );
      } on ClientException catch (error) {
        await store.remove(_pendingKey);
        return _handleConflict(error, cart);
      } on ApiException {
        return const CheckoutFailure(
          'The first request may have placed your order, but its response was lost. Check My orders before trying again.',
          canRetry: true,
        );
      }
    } on ClientException catch (error) {
      await store.remove(_pendingKey);
      return _handleConflict(error, cart);
    } on ApiException catch (error) {
      if (error is ServerException && error.code == 'STORE_CLOSED') {
        return const CheckoutFailure(
          'The store is closed. This checkout may have already been placed; check My orders before trying again.',
          canRetry: true,
        );
      }
      return CheckoutFailure(
        'The order response could not be confirmed. It may have been placed. Check My orders before trying again.',
        canRetry: error.isTransient,
      );
    }
  }

  Future<CheckoutResult> _handleConflict(
    ClientException error,
    Cart cart,
  ) async {
    if ({
      'PRODUCT_UNAVAILABLE',
      'PRICE_CHANGED',
      'QUANTITY_LIMIT',
      'INSUFFICIENT_STOCK',
      'COUPON_INVALID',
      'TOTAL_MISMATCH',
    }.contains(error.code)) {
      try {
        final latest = await ref.read(cartReconcilerProvider).reconcile(cart);
        if (ref.read(cartControllerProvider) == cart && latest.cart != cart) {
          await ref.read(cartControllerProvider.notifier).replace(latest.cart);
        }
        return CheckoutNeedsReview(
          latest,
          message: latest.hasChanges
              ? 'The server changed your cart. Review the updated items and total before ordering.'
              : 'The server total changed. Review the current cart total before ordering again.',
        );
      } on ApiException {
        return const CheckoutFailure(
          'The server rejected this order. Reconnect to refresh your cart before trying again.',
          canRetry: true,
        );
      }
    }
    if (error.code == 'STORE_CLOSED') {
      return const CheckoutFailure('The store closed before your order was placed.');
    }
    return CheckoutFailure(error.message, canRetry: error.isTransient);
  }
}

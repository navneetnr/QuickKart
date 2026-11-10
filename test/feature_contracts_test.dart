import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/app_config/data/config_repository.dart';
import 'package:quickkart/features/app_config/domain/app_config.dart';
import 'package:quickkart/features/app_config/domain/home_layout.dart';
import 'package:quickkart/features/app_config/domain/update_policy.dart';
import 'package:quickkart/features/app_config/presentation/app_config_controller.dart';
import 'package:quickkart/features/cart/application/cart_reconciler.dart';
import 'package:quickkart/features/cart/application/cart_controller.dart';
import 'package:quickkart/features/cart/data/cart_storage.dart';
import 'package:quickkart/features/cart/domain/cart.dart';
import 'package:quickkart/features/cart/domain/cart_pricing.dart';
import 'package:quickkart/features/cart/domain/reconciliation.dart';
import 'package:quickkart/features/catalog/data/catalog_repository.dart';
import 'package:quickkart/features/checkout/application/checkout_controller.dart';

import 'helpers/test_harness.dart';

void main() {
  test('home layout ignores unknown and duplicate IDs and preserves order', () {
    expect(
      HomeLayout.parse('["deals","video","banner","deals"]'),
      [HomeSection.deals, HomeSection.banner],
    );
    expect(HomeLayout.parse(null), HomeLayout.defaultSections);
    expect(HomeLayout.parse('[banner,'), HomeLayout.defaultSections);
    expect(HomeLayout.parse('["future"]'), HomeLayout.defaultSections);
  });

  test('update policy distinguishes required and optional versions', () {
    expect(
      UpdatePolicy.evaluate(
        currentVersion: '1.4.0',
        minSupportedVersion: '2.0.0',
        latestVersion: '2.1.0',
      ),
      UpdateRequirement.required,
    );
    expect(
      UpdatePolicy.evaluate(
        currentVersion: '1.4.0',
        minSupportedVersion: '1.0.0',
        latestVersion: '1.5.0',
      ),
      UpdateRequirement.optional,
    );
  });

  test('free delivery starts exactly at configured threshold', () {
    final cart = Cart(lines: [
      CartLine(
        productId: 'threshold',
        name: 'Threshold item',
        emoji: 'x',
        unit: '1 pc',
        unitPricePaise: 19900,
        quantity: 1,
        maxPerOrder: 1,
      ),
    ]);
    final pricing = CartPricing.compute(cart, AppConfig.defaults());
    expect(pricing.deliveryFeePaise, 0);
    expect(pricing.totalPaise, 19900);
  });

  test('remote config falls back to last-known-good values offline', () async {
    final h = TestHarness();
    addTearDown(h.dispose);
    h.server.publishConfig({'store_closed_message': 'Saved message'});
    final repository = h.read(configRepositoryProvider);
    final online = await repository.load();
    h.server.chaos.offline = true;
    final offline = await repository.load();
    expect(online.storeClosedMessage, 'Saved message');
    expect(offline.storeClosedMessage, 'Saved message');
  });

  test('cart reconciler returns typed price changes and the updated cart', () async {
    final h = TestHarness();
    addTearDown(h.dispose);
    final product = h.server.product('fruits-01');
    final cart = Cart(lines: [CartLine.fromProduct(product)]);
    h.server.setPrice(product.id, product.pricePaise + 100);

    final result = await h.read(cartReconcilerProvider).reconcile(cart);
    expect(result.requiresUserReview, isTrue);
    expect(result.cart.lines.single.unitPricePaise, product.pricePaise + 100);
    expect(result.changes.single, isA<PriceChanged>());
  });

  test('removed cart lines remain removed after app restart', () async {
    final h = TestHarness();
    addTearDown(h.dispose);
    final product = h.server.product('fruits-01');
    final initial = Cart(lines: [CartLine.fromProduct(product)]);
    h.read(cartControllerProvider.notifier).hydrate(initial);
    await h.read(cartControllerProvider.notifier).remove(product.id);

    final restarted = h.restart();
    addTearDown(restarted.dispose);
    expect(await restarted.read(cartStorageProvider).load(), const Cart.empty());
  });

  test('simultaneous cart quantity updates are serialized', () async {
    final h = TestHarness();
    addTearDown(h.dispose);
    final product = h.server.product('fruits-01');
    h.read(cartControllerProvider.notifier)
        .hydrate(Cart(lines: [CartLine.fromProduct(product)]));
    await Future.wait([
      h.read(cartControllerProvider.notifier).increment(product.id),
      h.read(cartControllerProvider.notifier).increment(product.id),
      h.read(cartControllerProvider.notifier).increment(product.id),
    ]);

    expect(h.read(cartControllerProvider).quantityOf(product.id), 4);
    expect((await h.read(cartStorageProvider).load()).quantityOf(product.id), 4);
  });

  test('lost order response retry reuses its key and creates one order', () async {
    final h = TestHarness();
    addTearDown(h.dispose);
    final product = h.server.product('fruits-01');
    h.read(cartControllerProvider.notifier)
        .hydrate(Cart(lines: [CartLine.fromProduct(product)]));
    h.server.chaos.loseNextOrderResponses++;

    final result = await h
        .read(checkoutControllerProvider.notifier)
        .placeOrder();
    expect(result, isA<CheckoutSuccess>());
    expect(h.server.orderCount, 1);
  });

  test('known closed store prevents the order request', () async {
    final h = TestHarness();
    addTearDown(h.dispose);
    final product = h.server.product('fruits-01');
    h.read(cartControllerProvider.notifier)
        .hydrate(Cart(lines: [CartLine.fromProduct(product)]));
    h.read(appConfigControllerProvider.notifier).hydrate(
          AppConfig.fromValues({'store_open': false}),
        );

    final result = await h
        .read(checkoutControllerProvider.notifier)
        .placeOrder();
    expect(result, isA<CheckoutFailure>());
    expect(h.server.orderCount, 0);
  });

  test('pull refresh fetches fresh product data after a price change', () async {
    final h = TestHarness();
    addTearDown(h.dispose);
    final repository = h.read(catalogRepositoryProvider);
    final before = await repository.getPage(categoryId: 'all');
    final product = before.items.first;
    h.server.setPrice(product.id, product.pricePaise + 200);

    final after = await repository.getPage(
      categoryId: 'all',
      forceRefresh: true,
    );
    expect(after.items.firstWhere((item) => item.id == product.id).pricePaise,
        product.pricePaise + 200);
  });
}

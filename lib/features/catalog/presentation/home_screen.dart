import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../app_config/domain/app_config.dart';
import '../../app_config/domain/home_layout.dart';
import '../../app_config/presentation/app_config_controller.dart';
import '../../cart/presentation/cart_badge_button.dart';
import '../../dev_tools/dev_tools_screen.dart';
import '../../orders/presentation/orders_screen.dart';
import '../../search/search_screen.dart';
import '../data/catalog_repository.dart';
import 'catalog_controller.dart';
import 'category_screen.dart';
import 'widgets/product_card.dart';

final _dealsProvider = FutureProvider<CatalogPage>(
  (ref) => ref.watch(catalogRepositoryProvider).getDeals(limit: 10, forceRefresh: true),
);

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_loadMoreNearEnd);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_loadMoreNearEnd)
      ..dispose();
    super.dispose();
  }

  void _loadMoreNearEnd() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      ref.read(catalogControllerProvider(kAllProductsCategory).notifier).loadMore();
    }
  }

  Future<void> _refresh() async {
    await Future.wait([
      ref.read(catalogControllerProvider(kAllProductsCategory).notifier).refresh(),
      ref.refresh(categoriesProvider.future),
      ref.refresh(_dealsProvider.future),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(appConfigControllerProvider);
    final storeName = ref.watch(mockServerProvider).storeName;
    final catalog = ref.watch(catalogControllerProvider(kAllProductsCategory));
    final catalogController = ref.read(
      catalogControllerProvider(kAllProductsCategory).notifier,
    );
    final sections = HomeLayout.parse(config.homeSectionsJson);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(storeName, style: const TextStyle(fontWeight: FontWeight.bold)),
            const Text('Delivery in 10 minutes ⚡', style: TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Dev tools',
            icon: const Icon(Icons.bug_report_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const DevToolsScreen(),
            )),
          ),
          IconButton(
            tooltip: 'My orders',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const OrdersScreen(),
            )),
          ),
          const CartBadgeButton(),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (!config.storeOpen)
              SliverToBoxAdapter(
                child: Container(
                  width: double.infinity,
                  color: Colors.red.shade700,
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    config.storeClosedMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            _SearchEntry(onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
            )),
            for (final section in sections)
              switch (section) {
                HomeSection.banner => _BannerSliver(banner: config.homeBanner),
                HomeSection.categories => const _CategoriesSliver(),
                HomeSection.deals => const _DealsSliver(),
                HomeSection.allProducts => _AllProductsSliver(
                    state: catalog,
                    controller: catalogController,
                  ),
              },
          ],
        ),
      ),
    );
  }
}

class _SearchEntry extends StatelessWidget {
  const _SearchEntry({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: InputDecorator(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search for products',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Search for products', style: TextStyle(color: Colors.grey)),
            ),
          ),
        ),
      );
}

class _BannerSliver extends StatelessWidget {
  const _BannerSliver({required this.banner});
  final HomeBanner? banner;

  @override
  Widget build(BuildContext context) {
    if (banner == null) return const SliverToBoxAdapter(child: SizedBox.shrink());
    final color = _parseColor(banner!.colorHex);
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(banner!.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
          if (banner!.subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(banner!.subtitle, style: const TextStyle(color: Colors.white)),
          ],
        ]),
      ),
    );
  }

  Color _parseColor(String value) {
    try {
      final hex = value.replaceFirst('#', '');
      final parsed = int.parse(hex, radix: 16);
      return Color(hex.length == 6 ? 0xFF000000 | parsed : parsed);
    } catch (_) {
      return Colors.deepOrange;
    }
  }
}

class _CategoriesSliver extends ConsumerWidget {
  const _CategoriesSliver();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 104,
        child: categories.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const Center(child: Text('Categories unavailable')),
          data: (items) => ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final category = items[index];
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => CategoryScreen(category: category),
                )),
                child: SizedBox(width: 76, child: Column(children: [
                  CircleAvatar(radius: 26, backgroundColor: Colors.green.shade50, child: Text(category.emoji, style: const TextStyle(fontSize: 24))),
                  const SizedBox(height: 4),
                  Text(category.name, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                ])),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DealsSliver extends ConsumerWidget {
  const _DealsSliver();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deals = ref.watch(_dealsProvider);
    return deals.when(
      loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
      error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
      data: (page) => page.items.isEmpty
          ? const SliverToBoxAdapter(child: SizedBox.shrink())
          : SliverToBoxAdapter(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 8), child: Text('Deals', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                SizedBox(height: 280, child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: page.items.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, index) => SizedBox(width: 170, child: ProductCard(product: page.items[index])),
                )),
              ]),
            ),
    );
  }
}

class _AllProductsSliver extends StatelessWidget {
  const _AllProductsSliver({required this.state, required this.controller});
  final CatalogState state;
  final CatalogController controller;

  @override
  Widget build(BuildContext context) {
    return SliverMainAxisGroup(slivers: [
      const SliverToBoxAdapter(child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Text('All products', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      )),
      if (state.fromCache)
        const SliverToBoxAdapter(child: Padding(
          padding: EdgeInsets.all(12),
          child: Text('Offline: showing saved products.'),
        )),
      if (state.isLoadingFirstPage)
        const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
      else if (state.items.isEmpty)
        SliverFillRemaining(hasScrollBody: false, child: Center(child: Text(state.errorMessage ?? 'No products here yet')))
      else ...[
        SliverPadding(
          padding: const EdgeInsets.all(12),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.62),
            delegate: SliverChildBuilderDelegate((context, index) => ProductCard(product: state.items[index]), childCount: state.items.length),
          ),
        ),
        SliverToBoxAdapter(child: Center(
          child: state.isLoadingMore
              ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator())
              : state.errorMessage != null
                  ? TextButton(onPressed: controller.loadMore, child: const Text('Retry loading products'))
                  : !state.hasMore
                      ? const Padding(padding: EdgeInsets.all(20), child: Text("You've seen it all"))
                      : const SizedBox(height: 24),
        )),
      ],
    ]);
  }
}

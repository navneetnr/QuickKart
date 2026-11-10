/// Sections the home screen knows how to render.
enum HomeSection { banner, categories, deals, allProducts }

/// Server-driven home screen layout.
///
/// ## TODO(F2) - implement [HomeLayout.parse]
///
/// Contract (checked by hidden tests):
/// * Input is the raw `home_sections` remote config value: a JSON array of
///   strings. Known ids: `banner`, `categories`, `deals`, `all_products`.
/// * Output keeps the order given by the config.
/// * Unknown idimport 'dart:convert';

/// Sections the home screen knows how to render.
enum HomeSection { banner, categories, deals, allProducts }

/// Server-driven home screen layout.
class HomeLayout {
  const HomeLayout._();

  static const List<HomeSection> defaultSections = [
    HomeSection.categories,
    HomeSection.allProducts,
  ];

  static List<HomeSection> parse(String? rawJson) {
    if (rawJson == null) return defaultSections;
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! List) return defaultSections;

      final sections = <HomeSection>[];
      final seen = <HomeSection>{};

      for (final item in decoded) {
        if (item is String) {
          HomeSection? section;
          switch (item) {
            case 'banner':
              section = HomeSection.banner;
              break;
            case 'categories':
              section = HomeSection.categories;
              break;
            case 'deals':
              section = HomeSection.deals;
              break;
            case 'all_products':
              section = HomeSection.allProducts;
              break;
          }
          // Ignore unknown IDs and duplicates (first occurrence wins)
          if (section != null && seen.add(section)) {
            sections.add(section);
          }
        }
      }

      if (sections.isEmpty) return defaultSections;
      return sections;
    } catch (_) {
      return defaultSections;
    }
  }
}s are ignored (older app versions must not break when the
///   backend adds a new section type).
/// * Duplicates are ignored (first occurrence wins).
/// * null, malformed JSON, a non-array value, or a result with zero known
///   sections -> [HomeLayout.defaultSections].
class HomeLayout {
  const HomeLayout._();

  static const List<HomeSection> defaultSections = [
    HomeSection.categories,
    HomeSection.allProducts,
  ];

  static List<HomeSection> parse(String? rawJson) {
    throw UnimplementedError('F2: implement HomeLayout.parse');
  }
}

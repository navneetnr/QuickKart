import 'dart:convert';

/// Sections the home screen knows how to render.
enum HomeSection { banner, categories, deals, allProducts }

/// Parses the server-provided section IDs, preserving order and ignoring
/// unknown IDs and duplicate sections.
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
      for (final id in decoded.whereType<String>()) {
        final section = switch (id) {
          'banner' => HomeSection.banner,
          'categories' => HomeSection.categories,
          'deals' => HomeSection.deals,
          'all_products' => HomeSection.allProducts,
          _ => null,
        };
        if (section != null && seen.add(section)) sections.add(section);
      }
      return sections.isEmpty ? defaultSections : sections;
    } on FormatException {
      return defaultSections;
    }
  }
}

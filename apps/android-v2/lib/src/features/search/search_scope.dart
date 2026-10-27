import '../../data/models.dart';

/// What a search shows. Shared by the TV and touch screens so the two can't
/// drift apart on which results each scope lists.
enum SearchScope {
  all('All'),
  movies('Movies'),
  shows('Shows'),
  people('People');

  const SearchScope(this.label);
  final String label;

  bool get showsTitles => this != people;
  bool get showsEpisodes => this == all;
  bool get showsPeople => this == all || this == people;

  /// The movies and shows this scope lists, in result order.
  List<CatalogItem> titles(List<CatalogItem> items) => [
    for (final i in items)
      if (switch (this) {
        movies => i.type == 'Movie',
        shows => i.type == 'Series',
        _ => i.type == 'Movie' || i.type == 'Series',
      })
        i,
  ];

  static List<CatalogItem> episodes(List<CatalogItem> items) => [
    for (final i in items)
      if (i.type == 'Episode') i,
  ];
}

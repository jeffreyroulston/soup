import '../../data/models.dart';
import '../../data/seerr_models.dart';

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

  /// The Seerr titles this scope lists, in result order.
  List<SeerrTitle> seerrTitles(List<SeerrTitle> titles) => [
    for (final t in titles)
      if (switch (this) {
        movies => t.mediaType == SeerrMediaType.movie,
        shows => t.mediaType == SeerrMediaType.tv,
        people => false,
        all => true,
      })
        t,
  ];

  static List<CatalogItem> episodes(List<CatalogItem> items) => [
    for (final i in items)
      if (i.type == 'Episode') i,
  ];
}

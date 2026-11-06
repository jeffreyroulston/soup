import 'package:flutter_test/flutter_test.dart';
import 'package:soup_v2/src/data/models.dart';
import 'package:soup_v2/src/data/seerr_models.dart';
import 'package:soup_v2/src/features/search/search_scope.dart';

const _items = [
  CatalogItem(id: 'm', name: 'Movie', type: 'Movie'),
  CatalogItem(id: 's', name: 'Show', type: 'Series'),
  CatalogItem(id: 'e', name: 'Episode', type: 'Episode'),
];

List<String> _ids(List<CatalogItem> items) => [for (final i in items) i.id];

void main() {
  test('each scope lists its own titles', () {
    expect(_ids(SearchScope.all.titles(_items)), ['m', 's']);
    expect(_ids(SearchScope.movies.titles(_items)), ['m']);
    expect(_ids(SearchScope.shows.titles(_items)), ['s']);
    expect(_ids(SearchScope.episodes(_items)), ['e']);
  });

  test('each scope lists its own Seerr titles', () {
    const movie = SeerrTitle(
      tmdbId: 1,
      mediaType: SeerrMediaType.movie,
      title: 'Movie',
    );
    const show = SeerrTitle(
      tmdbId: 2,
      mediaType: SeerrMediaType.tv,
      title: 'Show',
    );
    expect(SearchScope.all.seerrTitles([movie, show]), [movie, show]);
    expect(SearchScope.movies.seerrTitles([movie, show]), [movie]);
    expect(SearchScope.shows.seerrTitles([movie, show]), [show]);
    expect(SearchScope.people.seerrTitles([movie, show]), isEmpty);
  });

  test('sections shown per scope', () {
    expect(SearchScope.people.showsTitles, isFalse);
    expect(SearchScope.movies.showsEpisodes, isFalse);
    expect(SearchScope.all.showsEpisodes, isTrue);
    expect(SearchScope.shows.showsPeople, isFalse);
    expect(SearchScope.people.showsPeople, isTrue);
  });
}

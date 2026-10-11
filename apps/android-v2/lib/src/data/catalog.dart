import 'package:flutter/foundation.dart';

import 'models.dart';

/// Everything the UI reads or writes. Live impl: [JellyfinCatalog]; offline
/// design/testing impl: [MockCatalog].
abstract class Catalog extends ChangeNotifier {
  Future<List<CatalogItem>> libraries();
  Future<HomeData> home();
  Future<HomeExtras> homeExtras();
  Future<HomeCollection> homeCollection();
  Future<CuratedCollection?> curatedCollection(String id);
  Future<List<Shelf>> genreShelves();
  Future<List<Shelf>> becauseYouWatched();

  Future<CatalogItem> item(String id);
  Future<List<CatalogItem>> similar(String id);

  /// Direct children of a BoxSet/folder.
  Future<List<CatalogItem>> children(String parentId);
  Future<List<CatalogItem>> extras(CatalogItem item);
  Future<List<CatalogItem>> seasons(String seriesId);
  Future<List<CatalogItem>> episodes(String seriesId, String? seasonId);
  Future<CatalogItem?> seriesNextUp(String seriesId);
  Future<List<MediaSegment>> mediaSegments(String itemId);

  Future<List<CatalogItem>> libraryItems(CatalogItem library, LibrarySort sort);
  Future<int> libraryTotal(CatalogItem library);
  Future<List<GenreCount>> libraryGenres(CatalogItem library);

  Future<SearchResults> search(String term);
  Future<List<CatalogItem>> personItems(String personId);

  Future<void> setFavorite(String itemId, bool value);
  Future<void> setPlayed(String itemId, bool value);

  /// Artwork bytes, or null when the server has none. Goes through the
  /// Tailscale-aware HTTP client in live mode.
  Future<Uint8List?> image(ImageRef ref, {int maxWidth = 480});

  /// Bumped (and listeners notified) whenever cached data was invalidated, e.g.
  /// after a favourite or watched toggle, so screens can refetch.
  int get revision;
}

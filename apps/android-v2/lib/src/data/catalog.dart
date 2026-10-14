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

  /// The user's favourite movies, shows and episodes. Jellyfin keeps no
  /// "favourited on" date, so [LibrarySort.recentlyAdded] is library order.
  Future<List<CatalogItem>> favorites(LibrarySort sort);

  /// Movies and episodes the user has finished, most recently watched first.
  Future<List<CatalogItem>> history();

  Future<SearchResults> search(String term);
  Future<List<CatalogItem>> personItems(String personId);

  /// Favourite states set on this device, applied to the UI straight away
  /// rather than after the server round trip and refetch.
  final favoriteOverrides = ValueNotifier<Map<String, bool>>(const {});

  bool isFavorite(CatalogItem item) =>
      favoriteOverrides.value[item.id] ?? item.isFavorite;

  /// Optimistic: shows [value] immediately, reverts if the write fails.
  Future<void> setFavorite(String itemId, bool value) async {
    final previous = favoriteOverrides.value[itemId];
    favoriteOverrides.value = {...favoriteOverrides.value, itemId: value};
    try {
      await writeFavorite(itemId, value);
    } catch (_) {
      // Only undo if no later toggle has replaced ours.
      if (favoriteOverrides.value[itemId] == value) {
        final next = {...favoriteOverrides.value};
        if (previous == null) {
          next.remove(itemId);
        } else {
          next[itemId] = previous;
        }
        favoriteOverrides.value = next;
      }
      rethrow;
    }
  }

  @protected
  Future<void> writeFavorite(String itemId, bool value);

  Future<void> setPlayed(String itemId, bool value);

  /// Artwork bytes, or null when the server has none. Goes through the
  /// Tailscale-aware HTTP client in live mode.
  Future<Uint8List?> image(ImageRef ref, {int maxWidth = 480});

  /// One trickplay sprite sheet (see [Trickplay]), or null when it can't be
  /// loaded. Uncached; the player keeps the sheets it has fetched.
  Future<Uint8List?> trickplaySheet(
    String itemId,
    String? mediaSourceId,
    int width,
    int index,
  );

  /// Bumped (and listeners notified) whenever cached data was invalidated, e.g.
  /// after a favourite or watched toggle, so screens can refetch.
  int get revision;

  /// Drops cached data and has every screen reload (Retry, reconnect).
  void refresh() => notifyListeners();

  @override
  void dispose() {
    favoriteOverrides.dispose();
    super.dispose();
  }
}

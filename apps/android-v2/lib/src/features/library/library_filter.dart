import '../../data/models.dart';
import '../../utils/media.dart';

enum LibraryFilter { all, unwatched, inProgress, favourites }

const libraryFilterLabels = {
  LibraryFilter.all: 'All',
  LibraryFilter.unwatched: 'Unwatched',
  LibraryFilter.inProgress: 'In Progress',
  LibraryFilter.favourites: 'Favourites',
};

List<CatalogItem> applyLibraryFilter(
  List<CatalogItem> items,
  LibraryFilter filter,
  String? genre,
) => [
  for (final i in items)
    if ((genre == null || i.genres.contains(genre)) &&
        switch (filter) {
          LibraryFilter.all => true,
          LibraryFilter.unwatched => !i.played,
          LibraryFilter.inProgress => isInProgress(i),
          LibraryFilter.favourites => i.isFavorite,
        })
      i,
];

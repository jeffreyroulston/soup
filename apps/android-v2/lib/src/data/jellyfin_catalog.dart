import 'dart:async';
import 'dart:typed_data';

import 'package:soup_core/soup_core.dart';

import '../utils/media.dart';
import 'catalog.dart';
import 'curated_matcher.dart';
import 'models.dart';

const _detailFields =
    'Overview,ProductionYear,RunTimeTicks,OfficialRating,CommunityRating,CriticRating,MediaSources,MediaStreams,Genres,Studios,Networks,People,Path,Chapters,SortName,ChildCount,RemoteTrailers,LocalTrailerCount,SpecialFeatureCount,OriginalTitle,Tags,ProviderIds,Status,PremiereDate,EndDate,Trickplay';
const _listFields =
    'Overview,ProductionYear,RunTimeTicks,OfficialRating,CommunityRating,Genres,SortName,ChildCount,MediaStreams,DateCreated,DateLastMediaAdded';
const _curatedFields = 'ProviderIds,ProductionYear,SortName';
const _gridFields = 'ProductionYear,Genres,SortName';
const _nonVideoLibraries = {
  'boxsets',
  'playlists',
  'music',
  'books',
  'photos',
  'livetv',
};

/// Jellyfin only fills an episode's ParentBackdrop* (the show's backdrop) when
/// Thumb is also enabled, so a Backdrop request always asks for Thumb too.
Map<String, String> _listQuery(
  String imageTypes, [
  Map<String, String> extra = const {},
]) => {
  'Fields': _listFields,
  'EnableImageTypes':
      imageTypes.contains('Backdrop') && !imageTypes.contains('Thumb')
      ? '$imageTypes,Thumb'
      : imageTypes,
  'ImageTypeLimit': '1',
  ...extra,
};

/// Live catalog over [JellyfinApi]; port of apps/web/app/composables/useJellyfin.ts
/// plus a small TTL cache standing in for vue-query.
class JellyfinCatalog extends Catalog {
  JellyfinCatalog(this._api, this._session);

  final JellyfinApi _api;
  final JellyfinSession _session;
  int _revision = 0;

  @override
  int get revision => _revision;

  // ── cache ────────────────────────────────────────────────────────────────
  final _memo = <String, ({DateTime at, Future<Object?> value})>{};

  Future<T> _cached<T>(
    String key,
    Future<T> Function() load, {
    Duration ttl = const Duration(minutes: 2),
  }) {
    final hit = _memo[key];
    if (hit != null && DateTime.now().difference(hit.at) < ttl) {
      return hit.value as Future<T>;
    }
    final future = load();
    _memo[key] = (at: DateTime.now(), value: future);
    future.catchError((Object _) {
      _memo.remove(key);
      return null as T;
    });
    return future;
  }

  void invalidate() {
    _memo.clear();
    _revision++;
    notifyListeners();
  }

  @override
  void refresh() => invalidate();

  // ── helpers ──────────────────────────────────────────────────────────────
  Future<Object?> _get(String path, [Map<String, String>? query]) =>
      _api.getJson(_session, path, query: query);

  Future<Object?> _userItems(Map<String, String> query) =>
      _get('Users/${_session.userId}/Items', query);

  List<CatalogItem> _items(Object? value) {
    final raw = value is Map ? value['Items'] : value;
    if (raw is! List) return const [];
    return [for (final e in raw) ?CatalogItem.fromJson(e)];
  }

  // ── libraries / home ─────────────────────────────────────────────────────
  @override
  Future<List<CatalogItem>> libraries() => _cached('libraries', () async {
    return _items(
      await _get('Users/${_session.userId}/Views', {
        'IncludeExternalContent': 'false',
      }),
    );
  });

  @override
  Future<HomeData> home() => _cached('home', () async {
    // Logo: the hero shows title art over the backdrop when the item has it.
    const images = 'Primary,Backdrop,Logo';
    final results = await Future.wait<Object?>([
      _get(
        'Users/${_session.userId}/Items/Resume',
        _listQuery(images, {'Limit': '50', 'MediaTypes': 'Video'}),
      ),
      _get(
        'Shows/NextUp',
        _listQuery(images, {'UserId': _session.userId, 'Limit': '30'}),
      ).then<Object?>((v) => v).catchError((Object _) => null),
      libraries().then(
        (libs) => Future.wait([
          for (final lib in libs.where(
            (l) => !_nonVideoLibraries.contains(l.collectionType ?? ''),
          ))
            _latestShelf(lib, images),
        ]),
      ),
      _userItems(
        _listQuery(images, {
          'IncludeItemTypes': 'Movie,Series',
          'Recursive': 'true',
          'SortBy': 'Random',
          'ImageTypes': 'Backdrop',
          'Limit': '12',
        }),
      ).then<Object?>((v) => v).catchError((Object _) => null),
      // Play dates for Keep Watching's order: a Next Up episode is unplayed,
      // so its show's last watched episode says when you were last on it.
      _userItems({
        'IncludeItemTypes': 'Episode',
        'Recursive': 'true',
        'Filters': 'IsPlayed',
        'SortBy': 'DatePlayed',
        'SortOrder': 'Descending',
        'Limit': '200',
        'EnableImages': 'false',
      }).then<Object?>((v) => v).catchError((Object _) => null),
    ]);
    final resume = _items(results[0]);
    final collapsed = collapseKeepWatching(resume, [
      for (final item in _items(results[1]))
        if (!isFirstEpisode(item)) item,
    ]);
    return HomeData(
      resume: collapsed.resume,
      nextUp: collapsed.nextUp,
      keepWatching: orderKeepWatching(collapsed, [
        ...resume,
        ..._items(results[4]),
      ]),
      recentlyAdded: [
        for (final shelf in results[2]! as List<Shelf>)
          if (shelf.items.isNotEmpty) shelf,
      ],
      random: _items(results[3]),
    );
  }, ttl: const Duration(seconds: 30));

  Future<Shelf> _latestShelf(CatalogItem library, String images) async {
    final types = switch (library.collectionType) {
      'movies' => {'IncludeItemTypes': 'Movie'},
      'tvshows' => {'IncludeItemTypes': 'Episode', 'GroupItems': 'true'},
      _ => <String, String>{},
    };
    Object? raw;
    try {
      raw = await _get(
        'Users/${_session.userId}/Items/Latest',
        _listQuery(images, {'ParentId': library.id, 'Limit': '25', ...types}),
      );
    } on Object {
      raw = null;
    }
    return Shelf(
      title: library.name,
      items: _items(raw),
      libraryId: library.id,
    );
  }

  @override
  Future<HomeExtras> homeExtras() => _cached('homeExtras', () async {
    final results = await Future.wait([
      _rated('Primary,Backdrop', 9).catchError((Object _) => <CatalogItem>[]),
      _rated('Primary', 30, {
        'IsPlayed': 'false',
      }).catchError((Object _) => <CatalogItem>[]),
    ]);
    final topIds = {for (final i in results[0]) i.id};
    return HomeExtras(
      topRated: results[0],
      unwatchedTopRated: [
        for (final i in results[1])
          if (!topIds.contains(i.id)) i,
      ].take(20).toList(),
    );
  });

  Future<List<CatalogItem>> _rated(
    String images,
    int limit, [
    Map<String, String> extra = const {},
  ]) async {
    Future<List<CatalogItem>> query(
      int fetchLimit,
      Map<String, String> params,
    ) async => _items(
      await _userItems(
        _listQuery(images, {
          'Recursive': 'true',
          'SortBy': 'CommunityRating',
          'SortOrder': 'Descending',
          'HasCommunityRating': 'true',
          'Limit': '$fetchLimit',
          ...extra,
          ...params,
        }),
      ),
    );
    final results = await Future.wait([
      query(limit, {'IncludeItemTypes': 'Movie', 'MinCriticRating': '60'}),
      query(100, {
        'IncludeItemTypes': 'Series',
        'Fields': '$_listFields,RecursiveItemCount',
      }).then(
        (items) => [
          for (final i in items)
            if ((i.communityRating ?? 0) < 9.5 &&
                (i.recursiveItemCount ?? 0) >= 6)
              i,
        ],
      ),
    ]);
    final all = [...results[0], ...results[1]]
      ..sort(
        (a, b) => (b.communityRating ?? 0).compareTo(a.communityRating ?? 0),
      );
    return all.take(limit).toList();
  }

  Future<List<CatalogItem>> _libraryForCuratedMatch() =>
      _cached('curatedLibrary', () async {
        const pageSize = 500;
        Future<Object?> page(int start) => _userItems({
          'Fields': _curatedFields,
          'IncludeItemTypes': 'Movie,Series',
          'Recursive': 'true',
          'EnableImageTypes': 'Primary',
          'ImageTypeLimit': '1',
          'StartIndex': '$start',
          'Limit': '$pageSize',
        });
        final first = await page(0);
        final total = first is Map
            ? (first['TotalRecordCount'] as num?)?.toInt() ?? 0
            : 0;
        final rest = await Future.wait([
          for (
            var s = pageSize;
            s < (total < 10000 ? total : 10000);
            s += pageSize
          )
            page(s),
        ]);
        return [first, ...rest].expand(_items).toList();
      }, ttl: const Duration(minutes: 30));

  @override
  Future<HomeCollection> homeCollection() =>
      _cached('homeCollection', () async {
        List<CuratedCollection> curated;
        try {
          final library = await _libraryForCuratedMatch();
          curated = [
            for (final m in matchCuratedCollections(library)) m.toCollection(),
          ];
        } on Object {
          curated = const [];
        }
        SpotlightCollection? spotlight;
        if (curated.isEmpty) {
          try {
            spotlight = await _spotlight();
          } on Object {
            spotlight = null;
          }
        }
        return HomeCollection(curated: curated, spotlight: spotlight);
      }, ttl: const Duration(minutes: 30));

  Future<SpotlightCollection?> _spotlight() async {
    final sets = _items(
      await _userItems(
        _listQuery('Primary,Backdrop', {
          'IncludeItemTypes': 'BoxSet',
          'Recursive': 'true',
          'SortBy': 'Random',
          'Limit': '1',
        }),
      ),
    );
    if (sets.isEmpty) return null;
    final items = _items(
      await _userItems(
        _listQuery('Primary,Backdrop', {'ParentId': sets.first.id}),
      ),
    );
    return items.isEmpty
        ? null
        : SpotlightCollection(collection: sets.first, items: items);
  }

  @override
  Future<CuratedCollection?> curatedCollection(String id) async {
    final pack = getCuratedPack(id);
    if (pack == null) return null;
    final library = await _libraryForCuratedMatch();
    return matchCuratedPack(pack, library)?.toCollection();
  }

  @override
  Future<List<Shelf>> genreShelves() => _cached('genreShelves', () async {
    try {
      const titles = {'Recursive': 'true', 'IncludeItemTypes': 'Movie,Series'};
      final tally = countGenres(
        _items(
          await _userItems({
            ...titles,
            'Fields': 'Genres',
            'EnableTotalRecordCount': 'false',
            'EnableImages': 'false',
            'EnableUserData': 'false',
          }),
        ),
      );
      final pool = [
        for (final g in tally)
          if (g.count >= 8) g.name,
      ].take(12).toList();
      final picks = dailyShuffle(pool, 'genres').take(4).toList();
      final shelves = await Future.wait([
        for (final genre in picks)
          () async {
            Object? raw;
            try {
              raw = await _userItems(
                _listQuery('Primary', {
                  ...titles,
                  'Genres': genre,
                  'SortBy': 'CommunityRating',
                  'SortOrder': 'Descending',
                  'Limit': '60',
                }),
              );
            } on Object {
              raw = null;
            }
            return Shelf(
              title: genre,
              items: dailyShuffle(_items(raw), genre).take(20).toList(),
            );
          }(),
      ]);
      return [
        for (final s in shelves)
          if (s.items.length >= 4) s,
      ];
    } on Object {
      return <Shelf>[];
    }
  }, ttl: const Duration(minutes: 30));

  @override
  Future<List<Shelf>> becauseYouWatched() => _cached('byw', () async {
    try {
      final recent = _items(
        await _userItems({
          'Recursive': 'true',
          'IncludeItemTypes': 'Movie,Episode',
          'Filters': 'IsPlayed',
          'SortBy': 'DatePlayed',
          'SortOrder': 'Descending',
          'Limit': '20',
          'EnableImages': 'false',
        }),
      );
      final anchors = <String, String>{};
      for (final item in recent) {
        final id = item.seriesId ?? item.id;
        anchors.putIfAbsent(id, () => item.seriesName ?? item.name);
        if (anchors.length == 2) break;
      }
      final shelves = await Future.wait([
        for (final e in anchors.entries)
          () async {
            List<CatalogItem> sim;
            try {
              sim = await similar(e.key);
            } on Object {
              sim = const [];
            }
            return Shelf(
              title: 'Because You Watched ${e.value}',
              items: [
                for (final i in sim)
                  if (!anchors.containsKey(i.id)) i,
              ],
            );
          }(),
      ]);
      return [
        for (final s in shelves)
          if (s.items.length >= 4) s,
      ];
    } on Object {
      return <Shelf>[];
    }
  });

  // ── items ────────────────────────────────────────────────────────────────
  @override
  Future<CatalogItem> item(String id) => _cached('item:$id', () async {
    final raw = await _get('Users/${_session.userId}/Items/$id', {
      'Fields': _detailFields,
    });
    final item = CatalogItem.fromJson(raw);
    if (item == null) throw const JellyfinApiException('Unreadable item');
    return item;
  });

  @override
  Future<List<CatalogItem>> similar(String id) =>
      _cached('similar:$id', () async {
        try {
          return _items(
            await _get(
              'Items/$id/Similar',
              _listQuery('Primary,Backdrop', {
                'UserId': _session.userId,
                'Limit': '12',
              }),
            ),
          );
        } on Object {
          return <CatalogItem>[];
        }
      });

  @override
  Future<List<CatalogItem>> children(String parentId) =>
      _cached('children:$parentId', () async {
        return _items(
          await _userItems(
            _listQuery('Primary,Backdrop', {'ParentId': parentId}),
          ),
        );
      });

  @override
  Future<List<CatalogItem>> extras(CatalogItem item) =>
      _cached('extras:${item.id}', () async {
        Future<Object?> fetch(String path) async {
          try {
            return await _get('Items/${item.id}/$path', {
              'userId': _session.userId,
            });
          } on Object {
            return const [];
          }
        }

        final results = await Future.wait([
          if ((item.localTrailerCount ?? 0) > 0)
            fetch('LocalTrailers')
          else
            Future.value(const []),
          if ((item.specialFeatureCount ?? 0) > 0)
            fetch('SpecialFeatures')
          else
            Future.value(const []),
        ]);
        final trailers = _items(results[0]);
        final features = _items(results[1]);
        return [...trailers, ...features];
      });

  @override
  Future<List<CatalogItem>> seasons(String seriesId) =>
      _cached('seasons:$seriesId', () async {
        return _items(
          await _get(
            'Shows/$seriesId/Seasons',
            _listQuery('Primary', {'UserId': _session.userId}),
          ),
        );
      });

  @override
  Future<List<CatalogItem>> episodes(String seriesId, String? seasonId) =>
      _cached('episodes:$seriesId:$seasonId', () async {
        final query = _listQuery('Primary,Backdrop', {
          'UserId': _session.userId,
        });
        if (seasonId != null) query['SeasonId'] = seasonId;
        return _items(await _get('Shows/$seriesId/Episodes', query));
      });

  @override
  Future<CatalogItem?> seriesNextUp(String seriesId) =>
      _cached('nextUp:$seriesId', () async {
        try {
          final raw = await _get('Shows/NextUp', {
            'UserId': _session.userId,
            'SeriesId': seriesId,
            'Limit': '1',
            'Fields': _listFields,
            'EnableResumable': 'true',
            'DisableFirstEpisode': 'false',
          });
          return _items(raw).firstOrNull;
        } on Object {
          return null;
        }
      });

  @override
  Future<List<MediaSegment>> mediaSegments(String itemId) =>
      _cached('segments:$itemId', () async {
        try {
          final raw = await _get('MediaSegments/$itemId');
          final list = raw is Map ? raw['Items'] : null;
          if (list is! List) return <MediaSegment>[];
          const kinds = {
            'Intro': SegmentKind.intro,
            'Outro': SegmentKind.outro,
            'Recap': SegmentKind.recap,
            'Preview': SegmentKind.preview,
            'Commercial': SegmentKind.commercial,
          };
          return [
            for (final s in list)
              if (s is Map &&
                  kinds[s['Type']] != null &&
                  s['StartTicks'] is num &&
                  s['EndTicks'] is num &&
                  (s['EndTicks'] as num) > (s['StartTicks'] as num))
                MediaSegment(
                  kinds[s['Type']]!,
                  (s['StartTicks'] as num).toInt(),
                  (s['EndTicks'] as num).toInt(),
                ),
          ];
        } on Object {
          return <MediaSegment>[];
        }
      }, ttl: const Duration(minutes: 30));

  // ── library ──────────────────────────────────────────────────────────────
  Map<String, String> _libraryQuery(CatalogItem library) => {
    'ParentId': library.id,
    'Recursive': 'true',
    'IncludeItemTypes': library.collectionType == 'boxsets'
        ? 'BoxSet'
        : 'Movie,Series',
  };

  @override
  Future<List<CatalogItem>> libraryItems(
    CatalogItem library,
    LibrarySort sort,
  ) => _cached('lib:${library.id}:${sort.name}', () async {
    return _items(
      await _userItems({
        ..._libraryQuery(library),
        'SortBy': sort == LibrarySort.title
            ? 'SortName'
            : '${sort.apiValue},SortName',
        'SortOrder': sort.descending ? 'Descending' : 'Ascending',
        'Fields': _gridFields,
        'EnableTotalRecordCount': 'false',
        'EnableImageTypes': 'Primary',
        'ImageTypeLimit': '1',
      }),
    );
  });

  @override
  Future<int> libraryTotal(CatalogItem library) =>
      _cached('libTotal:${library.id}', () async {
        final raw = await _userItems({
          ..._libraryQuery(library),
          'Limit': '0',
          'EnableTotalRecordCount': 'true',
          'EnableImages': 'false',
          'EnableUserData': 'false',
        });
        return raw is Map ? (raw['TotalRecordCount'] as num?)?.toInt() ?? 0 : 0;
      });

  @override
  Future<List<GenreCount>> libraryGenres(CatalogItem library) =>
      _cached('libGenres:${library.id}', () async {
        return countGenres(
          _items(
            await _userItems({
              ..._libraryQuery(library),
              'Fields': 'Genres',
              'EnableTotalRecordCount': 'false',
              'EnableImages': 'false',
              'EnableUserData': 'false',
            }),
          ),
        );
      }, ttl: const Duration(minutes: 10));

  @override
  Future<List<CatalogItem>> history() => _cached('history', () async {
    return _items(
      await _userItems(
        _listQuery('Primary,Backdrop', {
          'Filters': 'IsPlayed',
          'Recursive': 'true',
          'IncludeItemTypes': 'Movie,Episode',
          'SortBy': 'DatePlayed',
          'SortOrder': 'Descending',
          'Limit': '200',
        }),
      ),
    );
  }, ttl: const Duration(minutes: 1));

  @override
  Future<List<CatalogItem>> favorites(LibrarySort sort) =>
      _cached('favorites:${sort.name}', () async {
        return _items(
          await _userItems(
            _listQuery('Primary,Backdrop', {
              'Filters': 'IsFavorite',
              'Recursive': 'true',
              'IncludeItemTypes': 'Movie,Series,Episode',
              'SortBy': sort == LibrarySort.title
                  ? 'SortName'
                  : '${sort.apiValue},SortName',
              'SortOrder': sort.descending ? 'Descending' : 'Ascending',
            }),
          ),
        );
      });

  // ── search ───────────────────────────────────────────────────────────────
  @override
  Future<SearchResults> search(String term) async {
    final trimmed = term.trim();
    if (trimmed.isEmpty) return const SearchResults();
    final results = await Future.wait<Object?>([
      _userItems(
        _listQuery('Primary,Backdrop', {
          'searchTerm': trimmed,
          'Recursive': 'true',
          'IncludeItemTypes': 'Movie,Series,Episode',
          'Limit': '40',
        }),
      ),
      _get('Persons', {
        'searchTerm': trimmed,
        'userId': _session.userId,
        'limit': '12',
        'enableImageTypes': 'Primary',
      }).then<Object?>((v) => v).catchError((Object _) => null),
    ]);
    final peopleRaw = results[1] is Map ? (results[1]! as Map)['Items'] : null;
    return SearchResults(
      items: _items(results[0]),
      people: [
        if (peopleRaw is List)
          for (final p in peopleRaw) ?Person.fromJson(p),
      ],
    );
  }

  @override
  Future<List<CatalogItem>> personItems(String personId) =>
      _cached('person:$personId', () async {
        return _items(
          await _userItems(
            _listQuery('Primary,Backdrop', {
              'PersonIds': personId,
              'Recursive': 'true',
              'IncludeItemTypes': 'Movie,Series',
              'SortBy': 'ProductionYear,SortName',
              'SortOrder': 'Descending',
            }),
          ),
        );
      });

  // ── writes ───────────────────────────────────────────────────────────────
  Future<void> _sendWithFallback(
    String method,
    String path,
    String legacyPath,
  ) async {
    try {
      await _api.sendRequest(
        _session,
        method,
        path,
        query: {'userId': _session.userId},
      );
    } on JellyfinApiException catch (e) {
      if (e.statusCode != 404 && e.statusCode != 405) rethrow;
      await _api.sendRequest(_session, method, legacyPath);
    }
  }

  @override
  Future<void> writeFavorite(String itemId, bool value) async {
    await _sendWithFallback(
      value ? 'POST' : 'DELETE',
      'UserFavoriteItems/$itemId',
      'Users/${_session.userId}/FavoriteItems/$itemId',
    );
    invalidate();
  }

  @override
  Future<void> setPlayed(String itemId, bool value) async {
    await _sendWithFallback(
      value ? 'POST' : 'DELETE',
      'UserPlayedItems/$itemId',
      'Users/${_session.userId}/PlayedItems/$itemId',
    );
    invalidate();
  }

  // ── images ───────────────────────────────────────────────────────────────
  final _images = <String, Future<Uint8List?>>{};
  static const _imageCacheSize = 400;

  @override
  Future<Uint8List?> trickplaySheet(
    String itemId,
    String? mediaSourceId,
    int width,
    int index,
  ) => _api
      .getBytes(
        _session,
        'Videos/$itemId/Trickplay/$width/$index.jpg',
        query: {'MediaSourceId': ?mediaSourceId},
      )
      .catchError((Object _) => null);

  @override
  Future<Uint8List?> image(ImageRef ref, {int maxWidth = 480}) {
    final tag = ref.tag;
    if (tag == null || tag.isEmpty) return Future.value(null);
    final key = '${ref.itemId}/${ref.type}/$tag/$maxWidth';
    final hit = _images.remove(key);
    if (hit != null) {
      _images[key] = hit;
      return hit;
    }
    final future = _api
        .getBytes(
          _session,
          'Items/${ref.itemId}/Images/${ref.type}',
          query: {'tag': tag, 'maxWidth': '$maxWidth', 'quality': '80'},
        )
        .catchError((Object _) => null);
    _images[key] = future;
    if (_images.length > _imageCacheSize) _images.remove(_images.keys.first);
    return future;
  }
}

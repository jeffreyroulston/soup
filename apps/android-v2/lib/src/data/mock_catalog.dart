import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show TextAlign;

import '../utils/media.dart';
import 'catalog.dart';
import 'curated_matcher.dart';
import 'models.dart';

/// In-memory catalog for design work and tests (`--dart-define=SOUP_MOCK=true`).
/// Ported in spirit from apps/web/app/utils/mockCatalog.ts; artwork is
/// generated gradients.
class MockCatalog extends Catalog {
  MockCatalog() {
    _build();
  }

  int _revision = 0;
  @override
  int get revision => _revision;

  final _items = <String, CatalogItem>{};
  final _children = <String, List<String>>{};
  final _libraryMembers = <String, List<String>>{};
  late final List<CatalogItem> _libraries;
  late final List<Person> _people;

  static const _min = 10000000 * 60;

  void _build() {
    final libs = [
      const CatalogItem(
        id: 'lib-movies',
        name: 'Movies',
        type: 'CollectionFolder',
        collectionType: 'movies',
      ),
      const CatalogItem(
        id: 'lib-tv',
        name: 'TV Shows',
        type: 'CollectionFolder',
        collectionType: 'tvshows',
      ),
      const CatalogItem(
        id: 'lib-collections',
        name: 'Collections',
        type: 'CollectionFolder',
        collectionType: 'boxsets',
      ),
    ];
    _libraries = libs;
    _people = const [
      Person(id: 'p1', name: 'Ada Meridian', role: 'Lead', type: 'Actor'),
      Person(id: 'p2', name: 'Jon Harbor', role: 'Detective', type: 'Actor'),
      Person(id: 'p3', name: 'Mira Solace', role: 'Director', type: 'Director'),
      Person(id: 'p4', name: 'Kai North', role: 'Writer', type: 'Writer'),
    ];

    // (id, name, year, rating, runtime min, genres, imdb, progress%)
    final movies =
        <(String, String, int, double, int, List<String>, String?, double)>[
          ('m1', 'Northlight', 2023, 8.4, 118, ['Drama', 'Sci-Fi'], null, 0),
          (
            'm2',
            'Glass Harbor',
            2022,
            7.9,
            104,
            ['Thriller', 'Mystery'],
            null,
            0.42,
          ),
          ('m3', 'Ember Road', 2021, 7.2, 96, ['Adventure', 'Drama'], null, 0),
          (
            'm4',
            'Paper Moon Circuit',
            2024,
            8.8,
            131,
            ['Sci-Fi', 'Adventure'],
            null,
            0,
          ),
          (
            'm5',
            'The Salt Line',
            2019,
            7.6,
            112,
            ['Thriller', 'Drama'],
            null,
            0.8,
          ),
          ('m6', 'Violet Hour', 2020, 8.1, 101, ['Romance', 'Drama'], null, 0),
          ('m7', 'Static Bloom', 2018, 6.9, 93, ['Comedy', 'Sci-Fi'], null, 0),
          ('m8', 'Iron Tide', 2017, 7.4, 125, ['Action', 'Adventure'], null, 0),
          (
            'm9',
            'Toy Story',
            1995,
            8.3,
            81,
            ['Animation', 'Comedy', 'Adventure'],
            'tt0114709',
            0,
          ),
          (
            'm10',
            'Finding Nemo',
            2003,
            8.2,
            100,
            ['Animation', 'Adventure', 'Comedy'],
            'tt0266543',
            0,
          ),
          (
            'm11',
            'The Incredibles',
            2004,
            8.0,
            115,
            ['Animation', 'Action', 'Adventure'],
            'tt0317705',
            0,
          ),
          (
            'm12',
            'Up',
            2009,
            8.3,
            96,
            ['Animation', 'Adventure', 'Comedy'],
            'tt1049413',
            0,
          ),
          (
            'm13',
            'Spirited Away',
            2001,
            8.6,
            125,
            ['Animation', 'Fantasy', 'Adventure'],
            'tt0245429',
            0,
          ),
          (
            'm14',
            'My Neighbor Totoro',
            1988,
            8.1,
            86,
            ['Animation', 'Fantasy', 'Family'],
            'tt0096283',
            0,
          ),
          (
            'm15',
            "Howl's Moving Castle",
            2004,
            8.2,
            119,
            ['Animation', 'Fantasy', 'Romance'],
            'tt0347149',
            0,
          ),
          (
            'm16',
            'Princess Mononoke',
            1997,
            8.3,
            134,
            ['Animation', 'Fantasy', 'Action'],
            'tt0119698',
            0,
          ),
        ];
    final movieIds = <String>[];
    for (final m in movies) {
      final runtime = m.$5 * _min;
      _items[m.$1] = CatalogItem(
        id: m.$1,
        name: m.$2,
        type: 'Movie',
        productionYear: m.$3,
        communityRating: m.$4,
        criticRating: 80,
        officialRating: 'PG-13',
        runTimeTicks: runtime,
        genres: m.$6,
        providerIds: {if (m.$7 case final imdb?) 'Imdb': imdb},
        overview:
            '${m.$2} is a ${m.$6.first.toLowerCase()} about people on the edge of something larger than themselves — made up for the mock library so layouts have real-looking copy to wrap around.',
        primaryImageTag: 'mock',
        backdropImageTag: 'mock',
        people: _people,
        studios: const ['Soup Pictures'],
        mediaStreams: const [
          MediaStreamInfo(
            index: 0,
            kind: StreamKind.video,
            width: 1920,
            height: 1080,
            codec: 'h264',
          ),
          MediaStreamInfo(
            index: 1,
            kind: StreamKind.audio,
            language: 'eng',
            displayTitle: 'English - AAC 5.1',
            isDefault: true,
            codec: 'aac',
          ),
          MediaStreamInfo(
            index: 2,
            kind: StreamKind.audio,
            language: 'jpn',
            displayTitle: 'Japanese - AAC 2.0',
            codec: 'aac',
          ),
          MediaStreamInfo(
            index: 3,
            kind: StreamKind.subtitle,
            language: 'eng',
            displayTitle: 'English',
            isTextSubtitle: true,
            codec: 'srt',
          ),
          MediaStreamInfo(
            index: 4,
            kind: StreamKind.subtitle,
            language: 'spa',
            displayTitle: 'Spanish',
            isTextSubtitle: true,
            codec: 'srt',
          ),
        ],
        chapters: [
          for (var i = 0; i < 6; i++)
            Chapter(name: 'Chapter ${i + 1}', startTicks: runtime ~/ 6 * i),
        ],
        playedPercentage: m.$8 == 0 ? null : m.$8 * 100,
        playbackPositionTicks: (runtime * m.$8).toInt(),
        localTrailerCount: 1,
        remoteTrailers: const [
          RemoteTrailer(
            url: 'https://www.youtube.com/watch?v=aqz-KE-bpKQ',
            name: 'Trailer',
          ),
        ],
      );
      movieIds.add(m.$1);
    }
    _libraryMembers['lib-movies'] = movieIds;

    final seriesIds = <String>[];
    void series(
      String id,
      String name,
      int year,
      double rating,
      List<String> genres,
      int seasons,
      String? imdb,
    ) {
      _items[id] = CatalogItem(
        id: id,
        name: name,
        type: 'Series',
        productionYear: year,
        communityRating: rating,
        officialRating: 'TV-MA',
        genres: genres,
        providerIds: {if (imdb != null) 'Imdb': imdb},
        overview:
            '$name follows an ensemble through $seasons season${seasons > 1 ? 's' : ''} of escalating consequences.',
        primaryImageTag: 'mock',
        backdropImageTag: 'mock',
        childCount: seasons,
        recursiveItemCount: seasons * 8,
        people: _people,
        status: 'Continuing',
      );
      final seasonIds = <String>[];
      for (var s = 1; s <= seasons; s++) {
        final sid = '$id-s$s';
        _items[sid] = CatalogItem(
          id: sid,
          name: 'Season $s',
          type: 'Season',
          indexNumber: s,
          seriesId: id,
          seriesName: name,
          primaryImageTag: 'mock',
        );
        seasonIds.add(sid);
        final eps = <String>[];
        for (var e = 1; e <= 4; e++) {
          final eid = '$id-s${s}e$e';
          _items[eid] = CatalogItem(
            id: eid,
            name: 'Episode title $e',
            type: 'Episode',
            seriesId: id,
            seriesName: name,
            seasonId: sid,
            parentIndexNumber: s,
            indexNumber: e,
            runTimeTicks: 44 * _min,
            primaryImageTag: 'mock',
            overview:
                'In episode $e the stakes shift and nobody agrees on what happened last night.',
            seriesPrimaryImageTag: 'mock',
            parentBackdropItemId: id,
            parentBackdropImageTag: 'mock',
            played: s == 1 && e <= 2,
            playedPercentage: s == 1 && e == 3 ? 35 : null,
            playbackPositionTicks: s == 1 && e == 3 ? 15 * _min : 0,
            mediaStreams: _items['m1']!.mediaStreams,
          );
          eps.add(eid);
        }
        _children[sid] = eps;
      }
      _children[id] = seasonIds;
      seriesIds.add(id);
    }

    series('s1', 'Signal Drift', 2022, 8.6, ['Sci-Fi', 'Drama'], 2, null);
    series('s2', 'After Kitchen', 2023, 8.1, ['Comedy', 'Drama'], 1, null);
    series(
      's3',
      'Arcane',
      2021,
      9.0,
      ['Animation', 'Action', 'Fantasy'],
      2,
      'tt11126994',
    );
    _libraryMembers['lib-tv'] = seriesIds;

    _items['b1'] = const CatalogItem(
      id: 'b1',
      name: 'Festival Night',
      type: 'BoxSet',
      overview: 'Four films for one long evening.',
      primaryImageTag: 'mock',
      backdropImageTag: 'mock',
      childCount: 4,
    );
    _children['b1'] = ['m1', 'm4', 'm6', 'm8'];
    _libraryMembers['lib-collections'] = ['b1'];
  }

  List<CatalogItem> get _movieItems => [
    for (final id in _libraryMembers['lib-movies']!) _items[id]!,
  ];
  List<CatalogItem> get _seriesItems => [
    for (final id in _libraryMembers['lib-tv']!) _items[id]!,
  ];
  List<CatalogItem> _byIds(Iterable<String> ids) => [
    for (final i in ids) _items[i]!,
  ];

  @override
  Future<List<CatalogItem>> libraries() async => _libraries;

  @override
  Future<HomeData> home() async {
    final resume = [
      for (final i in [
        ..._movieItems,
        ..._items.values.where((e) => e.type == 'Episode'),
      ])
        if (i.playbackPositionTicks > 0) i,
    ];
    final collapsed = collapseKeepWatching(resume, [_items['s2-s1e1']!]);
    return HomeData(
      resume: collapsed.resume,
      nextUp: collapsed.nextUp,
      recentlyAdded: [
        Shelf(
          title: 'Movies',
          items: _movieItems.reversed.take(12).toList(),
          libraryId: 'lib-movies',
        ),
        Shelf(title: 'TV Shows', items: _seriesItems, libraryId: 'lib-tv'),
      ],
    );
  }

  @override
  Future<HomeExtras> homeExtras() async {
    final rated = [..._movieItems, ..._seriesItems]
      ..sort(
        (a, b) => (b.communityRating ?? 0).compareTo(a.communityRating ?? 0),
      );
    return HomeExtras(
      topRated: rated.take(9).toList(),
      unwatchedTopRated: [
        for (final i in rated.skip(3))
          if (!i.played) i,
      ].take(10).toList(),
    );
  }

  @override
  Future<HomeCollection> homeCollection() async {
    final matched = matchCuratedCollections([..._movieItems, ..._seriesItems]);
    return HomeCollection(
      curated: [for (final m in matched) m.toCollection()],
      spotlight: SpotlightCollection(
        collection: _items['b1']!,
        items: _byIds(_children['b1']!),
      ),
    );
  }

  @override
  Future<CuratedCollection?> curatedCollection(String id) async {
    final pack = getCuratedPack(id);
    if (pack == null) return null;
    return matchCuratedPack(pack, [
      ..._movieItems,
      ..._seriesItems,
    ])?.toCollection();
  }

  @override
  Future<List<Shelf>> genreShelves() async {
    final tally = countGenres(_movieItems);
    return [
      for (final g in tally.take(2))
        Shelf(
          title: g.name,
          items: [
            for (final m in _movieItems)
              if (m.genres.contains(g.name)) m,
          ],
        ),
    ];
  }

  @override
  Future<List<Shelf>> becauseYouWatched() async => [
    Shelf(
      title: 'Because You Watched Glass Harbor',
      items: _movieItems.skip(2).take(8).toList(),
    ),
  ];

  @override
  Future<CatalogItem> item(String id) async {
    final i = _items[id];
    if (i == null) throw StateError('Unknown item $id');
    return i;
  }

  @override
  Future<List<CatalogItem>> similar(String id) async =>
      _movieItems.where((m) => m.id != id).take(8).toList();

  @override
  Future<List<CatalogItem>> children(String parentId) async =>
      _byIds(_children[parentId] ?? const []);

  @override
  Future<List<CatalogItem>> extras(CatalogItem item) async => const [];

  @override
  Future<List<CatalogItem>> seasons(String seriesId) async =>
      _byIds(_children[seriesId] ?? const []);

  @override
  Future<List<CatalogItem>> episodes(String seriesId, String? seasonId) async {
    final seasons = seasonId != null
        ? [seasonId]
        : (_children[seriesId] ?? const <String>[]);
    return [for (final s in seasons) ..._byIds(_children[s] ?? const [])];
  }

  @override
  Future<CatalogItem?> seriesNextUp(String seriesId) async {
    final eps = await episodes(seriesId, null);
    return eps.where((e) => !e.played).firstOrNull;
  }

  @override
  Future<List<MediaSegment>> mediaSegments(String itemId) async => [
    const MediaSegment(SegmentKind.intro, 30 * 10000000, 75 * 10000000),
  ];

  @override
  Future<List<CatalogItem>> libraryItems(
    CatalogItem library,
    LibrarySort sort,
  ) async {
    final list = _byIds(_libraryMembers[library.id] ?? const []);
    int cmp(CatalogItem a, CatalogItem b) => switch (sort) {
      LibrarySort.title => sortTitle(a).compareTo(sortTitle(b)),
      LibrarySort.recentlyAdded => b.id.compareTo(a.id),
      LibrarySort.year => (b.productionYear ?? 0).compareTo(
        a.productionYear ?? 0,
      ),
      LibrarySort.rating => (b.communityRating ?? 0).compareTo(
        a.communityRating ?? 0,
      ),
    };
    return list..sort(cmp);
  }

  @override
  Future<int> libraryTotal(CatalogItem library) async =>
      (_libraryMembers[library.id] ?? const []).length;

  @override
  Future<List<GenreCount>> libraryGenres(CatalogItem library) async =>
      countGenres(_byIds(_libraryMembers[library.id] ?? const []));

  @override
  Future<SearchResults> search(String term) async {
    final t = term.trim().toLowerCase();
    if (t.isEmpty) return const SearchResults();
    return SearchResults(
      items: [
        for (final i in _items.values)
          if ((i.type == 'Movie' ||
                  i.type == 'Series' ||
                  i.type == 'Episode') &&
              i.name.toLowerCase().contains(t))
            i,
      ],
      people: [
        for (final p in _people)
          if (p.name.toLowerCase().contains(t)) p,
      ],
    );
  }

  @override
  Future<List<CatalogItem>> personItems(String personId) async => [
    ..._movieItems.take(5),
    ..._seriesItems,
  ];

  @override
  Future<void> writeFavorite(String itemId, bool value) async {
    _items[itemId] = _items[itemId]!.copyWith(isFavorite: value);
    _revision++;
    notifyListeners();
  }

  @override
  Future<void> setPlayed(String itemId, bool value) async {
    _items[itemId] = _items[itemId]!.copyWith(played: value);
    _revision++;
    notifyListeners();
  }

  // ── generated artwork ────────────────────────────────────────────────────
  final _images = <String, Future<Uint8List?>>{};

  @override
  Future<Uint8List?> image(ImageRef ref, {int maxWidth = 480}) {
    if (ref.tag == null) return Future.value(null);
    final key = '${ref.itemId}/${ref.type}/$maxWidth';
    return _images.putIfAbsent(key, () => _render(ref, maxWidth));
  }

  Future<Uint8List?> _render(ImageRef ref, int maxWidth) async {
    final item = _items[ref.itemId];
    final name = item?.name ?? ref.itemId;
    final backdrop = ref.type == 'Backdrop' || item?.type == 'Episode';
    final w = backdrop ? 640.0 : 400.0;
    final h = backdrop ? 360.0 : 600.0;
    final hue = (name.codeUnits.fold<int>(7, (a, b) => a * 31 + b) % 360)
        .toDouble();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final top = _hsl(hue, .42, .22);
    final bottom = _hsl((hue + 40) % 360, .55, .12);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, w, h),
      ui.Paint()
        ..shader = ui.Gradient.linear(ui.Offset.zero, ui.Offset(w * .4, h), [
          top,
          bottom,
        ]),
    );
    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              textAlign: TextAlign.left,
              fontSize: backdrop ? 34 : 38,
              fontWeight: ui.FontWeight.w700,
            ),
          )
          ..pushStyle(ui.TextStyle(color: const ui.Color(0xFFF4F1EA)))
          ..addText(name);
    if (!backdrop) {
      final paragraph = builder.build()
        ..layout(ui.ParagraphConstraints(width: w - 48));
      canvas.drawParagraph(paragraph, ui.Offset(24, h - paragraph.height - 28));
    }
    final image = await recorder.endRecording().toImage(w.toInt(), h.toInt());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }

  ui.Color _hsl(double h, double s, double l) {
    final c = (1 - (2 * l - 1).abs()) * s;
    final x = c * (1 - ((h / 60) % 2 - 1).abs());
    final m = l - c / 2;
    final (r, g, b) = switch (h ~/ 60) {
      0 => (c, x, 0.0),
      1 => (x, c, 0.0),
      2 => (0.0, c, x),
      3 => (0.0, x, c),
      4 => (x, 0.0, c),
      _ => (c, 0.0, x),
    };
    int ch(double v) => ((v + m) * 255).round().clamp(0, 255);
    return ui.Color.fromARGB(255, ch(r), ch(g), ch(b));
  }
}

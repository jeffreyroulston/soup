import 'package:flutter_test/flutter_test.dart';
import 'package:soup_v2/src/data/curated_matcher.dart';
import 'package:soup_v2/src/data/curated_pack.dart';
import 'package:soup_v2/src/data/curated_packs.g.dart';
import 'package:soup_v2/src/data/mock_catalog.dart';
import 'package:soup_v2/src/data/models.dart';
import 'package:soup_v2/src/utils/media.dart';

CatalogItem _movie(String id, String name, int year, {String? imdb}) =>
    CatalogItem(
      id: id,
      name: name,
      type: 'Movie',
      productionYear: year,
      providerIds: {if (imdb != null) 'Imdb': imdb},
    );

void main() {
  group('CatalogItem.fromJson', () {
    test('maps user data, images and streams', () {
      final item = CatalogItem.fromJson({
        'Id': 'e1',
        'Name': 'Pilot',
        'Type': 'Episode',
        'SeriesId': 's1',
        'SeriesName': 'Show',
        'SeriesPrimaryImageTag': 'sp',
        'ImageTags': {'Primary': 'p'},
        'ParentBackdropItemId': 's1',
        'ParentBackdropImageTags': ['b'],
        'ParentIndexNumber': 1,
        'IndexNumber': 2,
        'UserData': {
          'IsFavorite': true,
          'Played': false,
          'PlaybackPositionTicks': 200000000,
          'PlayedPercentage': 12.5,
        },
        'MediaSources': [
          {
            'Id': 'src',
            'MediaStreams': [
              {'Type': 'Video', 'Index': 0, 'Width': 1920},
              {'Type': 'Subtitle', 'Index': 2, 'Codec': 'SRT'},
            ],
          },
        ],
      })!;
      expect(item.isFavorite, isTrue);
      expect(item.poster.itemId, 's1'); // episodes use the series poster
      expect(item.landscape.itemId, 'e1'); // ...but their own still for 16:9
      expect(item.backdrop.itemId, 's1');
      expect(item.hasBackdrop, isTrue);
      expect(item.mediaSourceId, 'src');
      expect(item.streamsOf(StreamKind.subtitle).single.isTextSubtitle, isTrue);
      expect(episodeCode(item), 'Season 1, Episode 2');
      expect(canResume(item), isTrue);
    });

    test('rejects entries with no id or name', () {
      expect(CatalogItem.fromJson({'Name': 'x'}), isNull);
      expect(CatalogItem.fromJson({'Id': 'x'}), isNull);
    });
  });

  group('media utils', () {
    test('runtime and time-left labels', () {
      expect(runtimeLabel(94 * 600000000), '1 hr 34 min');
      expect(runtimeLabel(26 * 600000000), '26 min');
      expect(runtimeLabel(60 * 600000000), '1 hr');
      expect(runtimeLabel(null), isNull);
    });

    test('dailyShuffle is stable for a day and varies by salt', () {
      final day = DateTime(2026, 10, 11);
      final a = dailyShuffle(List.generate(20, (i) => i), 'x', day);
      final b = dailyShuffle(List.generate(20, (i) => i), 'x', day);
      final c = dailyShuffle(List.generate(20, (i) => i), 'y', day);
      expect(a, b);
      expect(a, isNot(c));
      expect(a.toSet(), List.generate(20, (i) => i).toSet());
    });

    test(
      'collapseKeepWatching keeps the earliest part-watched episode per show',
      () {
        CatalogItem ep(String id, int s, int e, String series) => CatalogItem(
          id: id,
          name: id,
          type: 'Episode',
          seriesId: series,
          parentIndexNumber: s,
          indexNumber: e,
        );
        final out = collapseKeepWatching(
          [ep('a3', 1, 3, 'A'), _movie('m', 'M', 2020), ep('a1', 1, 1, 'A')],
          [ep('a9', 1, 9, 'A'), ep('b1', 1, 1, 'B')],
        );
        expect([for (final i in out.resume) i.id], ['a1', 'm']);
        expect([for (final i in out.nextUp) i.id], ['b1']); // A already shown
      },
    );

    test('countGenres sorts by count then name', () {
      final counts = countGenres([
        const CatalogItem(
          id: '1',
          name: 'a',
          type: 'Movie',
          genres: ['Drama', 'Comedy'],
        ),
        const CatalogItem(id: '2', name: 'b', type: 'Movie', genres: ['Drama']),
      ]);
      expect([for (final g in counts) g.name], ['Drama', 'Comedy']);
    });
  });

  group('curated packs', () {
    test('generated list has the web packs', () {
      expect(curatedPacks.length, greaterThan(20));
      expect(getCuratedPack('pixar'), isNotNull);
      expect(getCuratedPack('halloween')!.season, isNotNull);
    });

    test('seasonal windows, including one that wraps New Year', () {
      final christmas = getCuratedPack('christmas')!;
      expect(isPackInSeason(christmas, DateTime(2026, 12, 25)), isTrue);
      expect(isPackInSeason(christmas, DateTime(2027, 1, 1)), isTrue);
      expect(isPackInSeason(christmas, DateTime(2026, 6, 1)), isFalse);
    });

    test('matches by imdb id, then title+year, and needs minMatches', () {
      final pixar = getCuratedPack('pixar')!;
      final entries = pixar.entries.take(pixar.minMatches).toList();
      final library = [
        for (var i = 0; i < entries.length; i++)
          i.isEven
              ? _movie('m$i', 'Different Title $i', 1900, imdb: entries[i].imdb)
              : _movie('m$i', entries[i].name, entries[i].year ?? 0),
      ];
      expect(matchCuratedPack(pixar, library, DateTime(2026, 6, 1)), isNotNull);
      expect(
        matchCuratedPack(
          pixar,
          library.take(pixar.minMatches - 1).toList(),
          DateTime(2026, 6, 1),
        ),
        isNull,
      );
    });

    test('count label follows the web rules', () {
      CuratedCollection of(List<CatalogItem> items) => CuratedCollection(
        id: 'x',
        title: 't',
        description: 'd',
        items: items,
        theme: const CuratedTheme(bg: 0, accent: 0, mid: 0, label: 0),
      );
      final series = const CatalogItem(id: 's', name: 's', type: 'Series');
      expect(of([_movie('1', 'a', 1)]).countLabel, '1 film');
      expect(
        of([_movie('1', 'a', 1), _movie('2', 'b', 2)]).countLabel,
        '2 films',
      );
      expect(of([series]).countLabel, '1 series');
      expect(of([series, _movie('1', 'a', 1)]).countLabel, '2 titles');
    });
  });

  group('MockCatalog', () {
    test('lights up curated packs and toggles update items', () async {
      final catalog = MockCatalog();
      final home = await catalog.homeCollection();
      expect(home.curated.map((c) => c.id), containsAll(['pixar', 'ghibli']));
      var notified = 0;
      catalog.addListener(() => notified++);
      await catalog.setFavorite('m1', true);
      expect((await catalog.item('m1')).isFavorite, isTrue);
      expect(notified, 1);
      final data = await catalog.home();
      expect(data.resume, isNotEmpty);
      expect(data.recentlyAdded, isNotEmpty);
    });
  });
}

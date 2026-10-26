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
    test('title art: own logo, else the series\' through parent fields', () {
      final movie = CatalogItem.fromJson({
        'Id': 'm',
        'Name': 'Film',
        'Type': 'Movie',
        'ImageTags': {'Primary': 'p', 'Logo': 'l'},
      })!;
      expect(movie.logo?.itemId, 'm');
      expect(movie.logo?.type, 'Logo');
      expect(movie.logo?.tag, 'l');
      final episode = CatalogItem.fromJson({
        'Id': 'e',
        'Name': 'Pilot',
        'Type': 'Episode',
        'ParentLogoItemId': 's',
        'ParentLogoImageTag': 'sl',
      })!;
      expect(episode.logo?.itemId, 's');
      expect(episode.logo?.tag, 'sl');
      expect(
        CatalogItem.fromJson({'Id': 'x', 'Name': 'X', 'Type': 'Movie'})!.logo,
        isNull,
      );
    });

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

  group('Trickplay', () {
    Map<String, Object?> info(int width) => {
      'Width': width,
      'Height': width * 9 ~/ 16,
      'TileWidth': 10,
      'TileHeight': 10,
      'ThumbnailCount': 250,
      'Interval': 10000,
    };

    test('keeps the width closest to 320 for each source', () {
      final item = CatalogItem.fromJson({
        'Id': 'm1',
        'Name': 'Movie',
        'MediaSources': [
          {'Id': 'a'},
        ],
        'Trickplay': {
          'a': {'480': info(480), '320': info(320)},
          'b': {
            '640': info(640),
            'bad': {'Width': 320},
          },
        },
      })!;
      expect(item.trickplay['a']!.width, 320);
      expect(item.trickplay['b']!.width, 640);
      expect(item.trickplayFor(null)!.sourceId, 'a');
      expect(item.trickplayFor('b')!.info.width, 640);
      expect(item.trickplayFor('gone')!.sourceId, 'a');
    });

    test('no Trickplay field means no thumbnails', () {
      final item = CatalogItem.fromJson({'Id': 'm1', 'Name': 'Movie'})!;
      expect(item.trickplay, isEmpty);
      expect(item.trickplayFor('a'), isNull);
    });

    test('frameAt finds the sheet and cell, clamped to the last thumbnail', () {
      final t = Trickplay.parse({
        's': {'320': info(320)},
      })['s']!;
      expect(t.frameAt(Duration.zero), (sheet: 0, x: 0, y: 0));
      // Thumbnail 123 → sheet 1, cell 23 → column 3, row 2.
      expect(t.frameAt(const Duration(seconds: 1235)), (
        sheet: 1,
        x: 3 * 320,
        y: 2 * 180,
      ));
      expect(t.frameAt(const Duration(hours: 5)), (
        sheet: 2,
        x: 9 * 320,
        y: 4 * 180,
      ));
      expect(t.frameAt(const Duration(seconds: -5)).sheet, 0);
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

    test('orderKeepWatching puts the most recently watched show first', () {
      CatalogItem ep(
        String id,
        String series, {
        int s = 1,
        int e = 2,
        String? at,
      }) => CatalogItem(
        id: id,
        name: id,
        type: 'Episode',
        seriesId: series,
        parentIndexNumber: s,
        indexNumber: e,
        lastPlayedDate: at,
      );
      final out = orderKeepWatching(
        (
          resume: [ep('death-note', 'DN', at: '2026-10-12T09:50:00Z')],
          nextUp: [ep('archer', 'AR'), ep('dexter', 'DX'), ep('undated', 'UD')],
        ),
        [
          ep('dexter-played', 'DX', at: '2026-10-13T10:27:00Z'),
          ep('archer-played', 'AR', at: '2026-10-10T04:40:00Z'),
        ],
      );
      expect(
        [for (final i in out) i.id],
        ['dexter', 'death-note', 'archer', 'undated'],
      );
      expect(isFirstEpisode(ep('pilot', 'TL', e: 1)), isTrue);
      expect(isFirstEpisode(ep('premiere', 'TL', s: 2, e: 1)), isFalse);
    });

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

  group('quality caps', () {
    CatalogItem film({int? width, int? bitrate}) => CatalogItem.fromJson({
      'Id': 'f',
      'Name': 'Film',
      'Type': 'Movie',
      'MediaSources': [
        {
          'Id': 'src',
          'Bitrate': ?bitrate,
          'MediaStreams': [
            {'Type': 'Video', 'Index': 0, 'Width': ?width},
          ],
        },
      ],
    })!;

    test('reads the source bitrate', () {
      expect(film(bitrate: 8234000).sourceBitrate, 8234000);
      expect(film().sourceBitrate, isNull);
    });

    test('only offers caps below the file\'s resolution and bitrate', () {
      final caps = qualityCapsFor(film(width: 1920, bitrate: 6000000));
      expect(caps.first.bitrate, 4000000);
      expect(caps.every((q) => q.height <= 1080 && q.bitrate < 6000000), true);
      expect(
        qualityCapsFor(film(width: 3840)).first.label,
        '4K',
        reason: 'unknown bitrate leaves every cap up to the resolution',
      );
      expect(qualityCapsFor(film(width: 1920)).first.bitrate, 20000000);
    });

    test('bitrate labels', () {
      expect(bitrateLabel(8234000), '8.2 Mbps');
      expect(bitrateLabel(24000000), '24 Mbps');
      expect(bitrateLabel(640000), '640 kbps');
    });
  });
}

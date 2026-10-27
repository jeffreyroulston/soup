import 'seerr.dart';
import 'seerr_models.dart';

/// Seerr-shaped JSON for mock mode, so Explore works without a server and
/// the real mappers in seerr_models.dart get exercised. Posters reuse the
/// bundled public-domain scans (assets/posters). Port of
/// apps/web/app/utils/mockSeerr.ts.
class MockSeerr extends Seerr {
  MockSeerr({
    this.user = const SeerrUser(
      id: 1,
      displayName: 'Mock Viewer',
      permissions: 32,
    ),
  });

  /// The linked Seerr account; null to exercise the "browse only" state.
  final SeerrUser? user;

  final _requests = <_MockRequest>[
    _MockRequest(1, 103, 2, const [], DateTime.utc(2026, 10, 20, 18, 12)),
    _MockRequest(2, 105, 1, const [], DateTime.utc(2026, 10, 25, 9, 40)),
    _MockRequest(3, 201, 2, const [1, 2], DateTime.utc(2026, 9, 2, 20, 5)),
  ];
  int _nextRequestId = 4;

  static const titles = <_MockTitle>[
    _MockTitle(
      101,
      SeerrMediaType.movie,
      'Metropolis',
      '1927-01-10',
      'metropolis',
      8.2,
      153,
      ['Drama', 'Science Fiction'],
      status: 5,
      jellyfinId: 'm1',
      overview:
          "In a futuristic city sharply divided between the working class and the city planners, the son of the city's mastermind falls in love with a working-class prophet.",
    ),
    _MockTitle(
      102,
      SeerrMediaType.movie,
      'The Cabinet of Dr. Caligari',
      '1920-02-27',
      'caligari',
      8.0,
      76,
      ['Horror', 'Mystery'],
      overview:
          'Hypnotist Dr. Caligari uses a somnambulist, Cesare, to commit murders.',
    ),
    _MockTitle(
      103,
      SeerrMediaType.movie,
      'The General',
      '1926-12-25',
      'the-general',
      8.1,
      78,
      ['Comedy', 'Action'],
      status: 3,
      overview:
          "When Union spies steal an engineer's beloved locomotive, he pursues it single-handedly and straight through enemy lines.",
    ),
    _MockTitle(
      104,
      SeerrMediaType.movie,
      'The Kid',
      '1921-01-21',
      'the-kid',
      8.2,
      68,
      ['Comedy', 'Drama'],
      overview:
          'The Tramp cares for an abandoned child, but events put their relationship in jeopardy.',
    ),
    _MockTitle(
      105,
      SeerrMediaType.movie,
      'Night of the Living Dead',
      '1968-10-01',
      'night-of-the-living-dead',
      7.8,
      96,
      ['Horror'],
      status: 2,
      overview: 'A group of people try to survive when the dead start to rise.',
    ),
    _MockTitle(
      106,
      SeerrMediaType.movie,
      'Charade',
      '1963-12-05',
      'charade',
      7.8,
      113,
      ['Comedy', 'Mystery', 'Romance'],
      overview:
          'Romance and suspense ensue in Paris as a woman is pursued by several men who want a fortune her murdered husband had stolen.',
    ),
    _MockTitle(
      201,
      SeerrMediaType.tv,
      'The Phantom of the Opera',
      '1925-11-15',
      'phantom-of-the-opera',
      7.6,
      45,
      ['Drama', 'Horror'],
      seasons: 3,
      status: 4,
      jellyfinId: 's1',
      overview:
          'A disfigured composer haunts the Paris Opera House and falls for a young soprano.',
    ),
    _MockTitle(
      202,
      SeerrMediaType.tv,
      'Safety Last!',
      '1923-04-01',
      'safety-last',
      8.1,
      30,
      ['Comedy'],
      seasons: 2,
      overview:
          'A boy leaves his small country town and heads to the big city to get a job.',
    ),
    _MockTitle(
      203,
      SeerrMediaType.tv,
      'The Gold Rush',
      '1925-06-26',
      'gold-rush',
      8.1,
      50,
      ['Adventure', 'Comedy'],
      seasons: 4,
      overview:
          'A prospector goes to the Klondike in search of gold and finds it and more.',
    ),
    _MockTitle(
      204,
      SeerrMediaType.tv,
      'Sunrise',
      '1927-09-23',
      'sunrise',
      8.0,
      55,
      ['Drama', 'Romance'],
      seasons: 1,
      overview:
          'A married farmer falls under the spell of a slatternly woman from the city.',
    ),
    _MockTitle(
      205,
      SeerrMediaType.tv,
      'His Girl Friday',
      '1940-01-18',
      'his-girl-friday',
      7.8,
      25,
      ['Comedy'],
      seasons: 5,
      overview:
          'A newspaper editor uses every trick in the book to keep his ace reporter ex-wife from remarrying.',
    ),
  ];

  static _MockTitle _titleOf(int tmdbId) =>
      titles.firstWhere((t) => t.id == tmdbId);

  /// Pending requests make a title "requested", approved ones "on its way".
  int? _mediaStatusFor(_MockTitle title) {
    if (title.status != null) return title.status;
    final own = _requests.where((r) => r.tmdbId == title.id && r.status != 3);
    if (own.any((r) => r.status == 2)) return 3;
    if (own.any((r) => r.status == 1)) return 2;
    return null;
  }

  Map<String, Object?> _rawRequest(
    _MockRequest request, {
    bool withMedia = true,
  }) {
    final title = _titleOf(request.tmdbId);
    final status = _mediaStatusFor(title) ?? 1;
    return {
      'id': request.id,
      'status': request.status,
      'is4k': false,
      'createdAt': request.createdAt.toIso8601String(),
      'updatedAt': request.createdAt.toIso8601String(),
      'requestedBy': {'id': 1, 'displayName': 'Mock Viewer', 'permissions': 32},
      'seasons': [
        for (final n in request.seasons) {'seasonNumber': n, 'status': status},
      ],
      if (withMedia)
        'media': {
          'id': title.id,
          'tmdbId': title.id,
          'mediaType': title.mediaType.apiValue,
          'status': status,
        },
    };
  }

  Map<String, Object?>? _mediaInfo(_MockTitle title) {
    final status = _mediaStatusFor(title);
    if (status == null) return null;
    final own = _requests.where((r) => r.tmdbId == title.id);
    return {
      'id': title.id,
      'tmdbId': title.id,
      'tvdbId': title.mediaType == SeerrMediaType.tv ? 70000 + title.id : null,
      'status': status,
      'jellyfinMediaId': title.jellyfinId,
      'seasons': [
        if (title.status == 4)
          for (var n = 1; n <= (title.seasons ?? 0); n++)
            {'seasonNumber': n, 'status': n == 1 ? 5 : 1},
      ],
      'requests': [for (final r in own) _rawRequest(r, withMedia: false)],
    };
  }

  Map<String, Object?> _rawTitle(_MockTitle title) => {
    'id': title.id,
    'mediaType': title.mediaType.apiValue,
    if (title.mediaType == SeerrMediaType.movie)
      'title': title.title
    else
      'name': title.title,
    if (title.mediaType == SeerrMediaType.movie)
      'releaseDate': title.date
    else
      'firstAirDate': title.date,
    'overview': title.overview,
    'posterPath': 'assets/posters/${title.poster}.jpg',
    'backdropPath': 'assets/posters/${title.poster}.jpg',
    'voteAverage': title.vote,
    'mediaInfo': _mediaInfo(title),
  };

  Map<String, Object?> _page(List<_MockTitle> list) => {
    'page': 1,
    'totalPages': 1,
    'totalResults': list.length,
    'results': [for (final t in list) _rawTitle(t)],
  };

  @override
  Future<SeerrStatus> fetchStatus() async => mapSeerrStatus({
    'configured': true,
    'reachable': true,
    'version': 'mock',
    if (user case final u?)
      'user': {
        'id': u.id,
        'displayName': u.displayName,
        'permissions': u.permissions,
      },
  });

  @override
  Future<SeerrSearchResults> search(String term, {int page = 1}) async {
    final needle = term.trim().toLowerCase();
    if (needle.isEmpty) return const SeerrSearchResults();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final hits = titles
        .where((t) => t.title.toLowerCase().contains(needle))
        .toList();
    final raw = _page(hits);
    if ('buster keaton'.contains(needle) || needle.contains('keaton')) {
      (raw['results'] as List<Object?>).add({
        'id': 901,
        'mediaType': 'person',
        'name': 'Buster Keaton',
        'knownFor': [_rawTitle(_titleOf(103))],
      });
    }
    return mapSeerrResults(raw);
  }

  @override
  Future<SeerrSearchResults> discover(String path, {int page = 1}) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final list = switch (path) {
      'discover/movies' =>
        titles.where((t) => t.mediaType == SeerrMediaType.movie).toList(),
      'discover/tv' =>
        titles.where((t) => t.mediaType == SeerrMediaType.tv).toList(),
      'discover/movies/upcoming' =>
        titles
            .where((t) => t.mediaType == SeerrMediaType.movie)
            .toList()
            .reversed
            .toList(),
      _ => titles.toList(),
    };
    return mapSeerrResults(_page(list));
  }

  @override
  Future<SeerrDetails?> details(SeerrMediaType type, int tmdbId) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final title = titles
        .where((t) => t.id == tmdbId && t.mediaType == type)
        .firstOrNull;
    if (title == null) return null;
    final raw = _rawTitle(title)
      ..addAll({
        'tagline': 'A ${title.genres.first.toLowerCase()} for the ages.',
        'runtime': title.runtime,
        'episodeRunTime': [title.runtime],
        'genres': [
          for (final g in title.genres) {'name': g},
        ],
        'status': type == SeerrMediaType.tv ? 'Ended' : null,
        'externalIds': {
          'imdbId': 'tt${1000000 + title.id}',
          'tvdbId': 70000 + title.id,
        },
        'seasons': [
          for (var n = 1; n <= (title.seasons ?? 0); n++)
            {
              'seasonNumber': n,
              'name': 'Season $n',
              'episodeCount': 6 + n,
              'airDate': '${yearOf(title.date)! + n - 1}-01-01',
            },
        ],
        'credits': {
          'cast': [
            {'id': 1, 'name': 'Ada Meridian', 'character': 'Lead'},
            {'id': 2, 'name': 'Jon Harbor', 'character': 'Detective'},
            {'id': 3, 'name': 'Mira Solace', 'character': 'The Stranger'},
          ],
        },
        'relatedVideos': [
          {
            'url': 'https://www.youtube.com/watch?v=aqz-KE-bpKQ',
            'type': 'Trailer',
          },
        ],
      });
    return mapSeerrDetails(raw, type);
  }

  @override
  Future<SeerrRequestsPage> myRequests(
    SeerrRequestFilter filter, {
    int take = 20,
    int skip = 0,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (user == null) return const SeerrRequestsPage();
    final all = _requests.where((r) {
      final status = _mediaStatusFor(_titleOf(r.tmdbId)) ?? 1;
      return switch (filter) {
        SeerrRequestFilter.all => true,
        SeerrRequestFilter.pending => r.status == 1,
        SeerrRequestFilter.processing => r.status == 2 && status == 3,
        SeerrRequestFilter.available => status == 5 || status == 4,
      };
    }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final slice = all.skip(skip).take(take).toList();
    return mapSeerrRequestsPage({
      'pageInfo': {
        'results': all.length,
        'pages': (all.length / take).ceil(),
        'page': skip ~/ take + 1,
      },
      'results': [for (final r in slice) _rawRequest(r)],
    });
  }

  @override
  Future<void> createRequest(SeerrRequestPayload payload) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (user == null) {
      throw const SeerrException(
        403,
        'seerr_user_not_linked',
        'No Seerr account is linked to your Jellyfin login.',
      );
    }
    final title = _titleOf(payload.mediaId);
    final seasons = payload.mediaType == SeerrMediaType.tv
        ? (payload.allSeasons
              ? [for (var n = 1; n <= (title.seasons ?? 0); n++) n]
              : payload.seasons ?? const <int>[])
        : const <int>[];
    _requests.add(
      _MockRequest(
        _nextRequestId++,
        payload.mediaId,
        1,
        seasons,
        DateTime.now().toUtc(),
      ),
    );
    invalidate();
  }

  @override
  Future<void> cancelRequest(int requestId) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    _requests.removeWhere((r) => r.id == requestId);
    invalidate();
  }
}

class _MockTitle {
  const _MockTitle(
    this.id,
    this.mediaType,
    this.title,
    this.date,
    this.poster,
    this.vote,
    this.runtime,
    this.genres, {
    this.seasons,
    this.status,
    this.jellyfinId,
    required this.overview,
  });
  final int id;
  final SeerrMediaType mediaType;
  final String title;
  final String date;
  final String poster;
  final double vote;
  final int runtime;
  final List<String> genres;
  final int? seasons;

  /// Seerr MediaStatus, when the library knows the title.
  final int? status;

  /// Which mock Jellyfin item the title is, when it's in the library.
  final String? jellyfinId;
  final String overview;
}

class _MockRequest {
  _MockRequest(this.id, this.tmdbId, this.status, this.seasons, this.createdAt);
  final int id;
  final int tmdbId;
  final int status;
  final List<int> seasons;
  final DateTime createdAt;
}

/// What Seerr (Jellyseerr/Overseerr) tells us through the Soup plugin, in
/// the app's own shapes. Port of apps/web/app/types/seerr.ts and the mapping
/// half of apps/web/app/utils/seerr.ts.
library;

enum SeerrMediaType {
  movie('movie', 'Movie'),
  tv('tv', 'Series');

  const SeerrMediaType(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static SeerrMediaType? parse(Object? value) => switch (value) {
    'movie' => movie,
    'tv' => tv,
    _ => null,
  };
}

/// Seerr `MediaStatus`: how much of a title the library holds.
enum SeerrMediaStatus {
  unknown(1),
  pending(2),
  processing(3),
  partiallyAvailable(4),
  available(5),
  deleted(6);

  const SeerrMediaStatus(this.code);
  final int code;

  static SeerrMediaStatus parse(Object? value) {
    final n = _num(value)?.toInt();
    for (final s in values) {
      if (s.code == n) return s;
    }
    return unknown;
  }
}

/// Seerr `MediaRequestStatus`: where a request stands with the approvers.
enum SeerrRequestStatus {
  pending(1),
  approved(2),
  declined(3),
  failed(4),
  completed(5);

  const SeerrRequestStatus(this.code);
  final int code;

  static SeerrRequestStatus parse(Object? value) {
    final n = _num(value)?.toInt();
    for (final s in values) {
      if (s.code == n) return s;
    }
    return pending;
  }
}

class SeerrSeasonStatus {
  const SeerrSeasonStatus(this.seasonNumber, this.status);
  final int seasonNumber;
  final SeerrMediaStatus status;
}

class SeerrRequester {
  const SeerrRequester({required this.id, required this.displayName});
  final int id;
  final String displayName;
}

class SeerrRequest {
  const SeerrRequest({
    required this.id,
    required this.status,
    required this.mediaType,
    required this.tmdbId,
    required this.mediaStatus,
    this.is4k = false,
    this.createdAt,
    this.seasons = const [],
    this.requestedBy,
  });

  final int id;
  final SeerrRequestStatus status;
  final bool is4k;
  final DateTime? createdAt;
  final SeerrMediaType mediaType;
  final int tmdbId;

  /// The title's library status, as of this request.
  final SeerrMediaStatus mediaStatus;

  /// Seasons this request covers (shows only).
  final List<SeerrSeasonStatus> seasons;
  final SeerrRequester? requestedBy;

  bool get isPending => status == SeerrRequestStatus.pending;
}

/// Seerr's record of a title: whether it's in the library and what's been
/// asked for. Null when nobody has touched it.
class SeerrMediaInfo {
  const SeerrMediaInfo({
    required this.id,
    required this.tmdbId,
    required this.status,
    this.tvdbId,
    this.jellyfinMediaId,
    this.seasons = const [],
    this.requests = const [],
  });

  final int id;
  final int tmdbId;
  final int? tvdbId;
  final SeerrMediaStatus status;

  /// The Jellyfin item Seerr matched the title to, when it's in the library.
  final String? jellyfinMediaId;
  final List<SeerrSeasonStatus> seasons;
  final List<SeerrRequest> requests;
}

/// A movie or show as Seerr lists it: TMDB data plus library status.
class SeerrTitle {
  const SeerrTitle({
    required this.tmdbId,
    required this.mediaType,
    required this.title,
    this.year,
    this.releaseDate,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.voteAverage,
    this.mediaInfo,
  });

  final int tmdbId;
  final SeerrMediaType mediaType;
  final String title;
  final int? year;
  final String? releaseDate;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;

  /// TMDB score out of 10.
  final double? voteAverage;
  final SeerrMediaInfo? mediaInfo;

  String get key => '${mediaType.apiValue}-$tmdbId';
}

class SeerrPerson {
  const SeerrPerson({
    required this.tmdbId,
    required this.name,
    this.profilePath,
    this.knownFor = const [],
  });
  final int tmdbId;
  final String name;
  final String? profilePath;
  final List<SeerrTitle> knownFor;
}

class SeerrSearchResults {
  const SeerrSearchResults({
    this.page = 1,
    this.totalPages = 1,
    this.totalResults = 0,
    this.titles = const [],
    this.people = const [],
  });
  final int page;
  final int totalPages;
  final int totalResults;
  final List<SeerrTitle> titles;
  final List<SeerrPerson> people;

  bool get isEmpty => titles.isEmpty && people.isEmpty;
}

class SeerrSeason {
  const SeerrSeason({
    required this.seasonNumber,
    required this.name,
    this.episodeCount = 0,
    this.airDate,
    this.posterPath,
    this.overview,
  });
  final int seasonNumber;
  final String name;
  final int episodeCount;
  final String? airDate;
  final String? posterPath;
  final String? overview;
}

class SeerrCastMember {
  const SeerrCastMember({
    required this.id,
    required this.name,
    this.character,
    this.profilePath,
  });
  final int id;
  final String name;
  final String? character;
  final String? profilePath;
}

/// One title in full: what the detail page shows.
class SeerrDetails extends SeerrTitle {
  const SeerrDetails({
    required super.tmdbId,
    required super.mediaType,
    required super.title,
    super.year,
    super.releaseDate,
    super.overview,
    super.posterPath,
    super.backdropPath,
    super.voteAverage,
    super.mediaInfo,
    this.tagline,
    this.runtime,
    this.genres = const [],
    this.status,
    this.contentRating,
    this.imdbId,
    this.tvdbId,
    this.seasons = const [],
    this.cast = const [],
    this.networks = const [],
    this.trailerUrl,
  });

  final String? tagline;

  /// Minutes: a movie's runtime, or a show's typical episode length.
  final int? runtime;
  final List<String> genres;

  /// A show's airing status from TMDB (Returning Series, Ended…).
  final String? status;
  final String? contentRating;
  final String? imdbId;
  final int? tvdbId;

  /// Shows: every season TMDB lists, specials (season 0) excluded.
  final List<SeerrSeason> seasons;
  final List<SeerrCastMember> cast;
  final List<String> networks;
  final String? trailerUrl;

  bool get isShow => mediaType == SeerrMediaType.tv;
}

/// Seerr permission bits (server/lib/permissions.ts).
abstract final class SeerrPermission {
  static const admin = 2;
  static const manageRequests = 16;
  static const request = 32;
  static const requestMovie = 262144;
  static const requestTv = 524288;
}

class SeerrUser {
  const SeerrUser({
    required this.id,
    required this.displayName,
    this.permissions = 0,
  });
  final int id;
  final String displayName;

  /// Seerr's permission bitmask; see [canRequest].
  final int permissions;

  bool has(int bit) =>
      (permissions & SeerrPermission.admin) == SeerrPermission.admin ||
      (permissions & bit) == bit;

  /// Whether Seerr would accept a request for this kind of title.
  bool canRequest(SeerrMediaType type) {
    if (has(SeerrPermission.request) || has(SeerrPermission.manageRequests)) {
      return true;
    }
    return has(
      type == SeerrMediaType.movie
          ? SeerrPermission.requestMovie
          : SeerrPermission.requestTv,
    );
  }
}

class SeerrStatus {
  const SeerrStatus({
    required this.configured,
    required this.reachable,
    this.version,
    this.user,
    this.error,
  });

  /// The plugin has a Seerr URL and key; the Explore tab shows when true.
  final bool configured;

  /// Seerr answered the plugin's probe.
  final bool reachable;
  final String? version;

  /// The Seerr account linked to the signed-in Jellyfin user; null means
  /// they can browse but not request.
  final SeerrUser? user;
  final String? error;

  bool get usable => configured && reachable;
}

/// What to ask Seerr for.
class SeerrRequestPayload {
  const SeerrRequestPayload({
    required this.mediaType,
    required this.mediaId,
    this.tvdbId,
    this.seasons,
    this.allSeasons = false,
    this.is4k = false,
  });
  final SeerrMediaType mediaType;
  final int mediaId;
  final int? tvdbId;

  /// Shows: the seasons to request, or [allSeasons].
  final List<int>? seasons;
  final bool allSeasons;
  final bool is4k;

  Map<String, Object?> toJson() => {
    'mediaType': mediaType.apiValue,
    'mediaId': mediaId,
    if (tvdbId != null) 'tvdbId': tvdbId,
    if (mediaType == SeerrMediaType.tv)
      'seasons': allSeasons ? 'all' : (seasons ?? const <int>[]),
    'is4k': is4k,
  };
}

enum SeerrRequestFilter {
  all('all', 'All'),
  pending('pending', 'Pending'),
  processing('processing', 'On the way'),
  available('available', 'In library');

  const SeerrRequestFilter(this.apiValue, this.label);
  final String apiValue;
  final String label;
}

class SeerrRequestsPage {
  const SeerrRequestsPage({
    this.total = 0,
    this.pages = 0,
    this.requests = const [],
  });
  final int total;
  final int pages;
  final List<SeerrRequest> requests;
}

// ── JSON ──────────────────────────────────────────────────────────────────

Map<Object?, Object?>? _obj(Object? value) =>
    value is Map<Object?, Object?> ? value : null;

String? _str(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;

num? _num(Object? value) => value is num && value.isFinite ? value : null;

List<Object?> _arr(Object? value) => value is List<Object?> ? value : const [];

int? yearOf(String? date) {
  if (date == null || date.length < 4) return null;
  final year = int.tryParse(date.substring(0, 4));
  return year != null && year > 1800 ? year : null;
}

List<SeerrSeasonStatus> _seasonStatuses(Object? value) => [
  for (final raw in _arr(value))
    if (_obj(raw) case final season? when _num(season['seasonNumber']) != null)
      SeerrSeasonStatus(
        _num(season['seasonNumber'])!.toInt(),
        SeerrMediaStatus.parse(season['status']),
      ),
];

SeerrRequester? _requester(Object? raw) {
  final user = _obj(raw);
  final id = user == null ? null : _num(user['id'])?.toInt();
  if (user == null || id == null) return null;
  return SeerrRequester(
    id: id,
    displayName:
        _str(user['displayName']) ??
        _str(user['username']) ??
        _str(user['jellyfinUsername']) ??
        _str(user['plexUsername']) ??
        'User $id',
  );
}

/// A request as Seerr lists it. The fallbacks cover `mediaInfo.requests`,
/// where `media` is omitted.
SeerrRequest? mapSeerrRequest(
  Object? raw, {
  SeerrMediaType? mediaType,
  int? tmdbId,
  SeerrMediaStatus? mediaStatus,
}) {
  final request = _obj(raw);
  final id = request == null ? null : _num(request['id'])?.toInt();
  if (request == null || id == null) return null;
  final media = _obj(request['media']);
  final type =
      (media == null ? null : SeerrMediaType.parse(media['mediaType'])) ??
      mediaType;
  final tmdb =
      (media == null ? null : _num(media['tmdbId'])?.toInt()) ?? tmdbId;
  if (type == null || tmdb == null) return null;
  final is4k = request['is4k'] == true;
  return SeerrRequest(
    id: id,
    status: SeerrRequestStatus.parse(request['status']),
    is4k: is4k,
    createdAt: DateTime.tryParse(_str(request['createdAt']) ?? ''),
    mediaType: type,
    tmdbId: tmdb,
    mediaStatus: media != null
        ? SeerrMediaStatus.parse(is4k ? media['status4k'] : media['status'])
        : mediaStatus ?? SeerrMediaStatus.unknown,
    seasons: _seasonStatuses(request['seasons']),
    requestedBy: _requester(request['requestedBy']),
  );
}

SeerrMediaInfo? mapSeerrMediaInfo(Object? raw, SeerrMediaType mediaType) {
  final info = _obj(raw);
  final id = info == null ? null : _num(info['id'])?.toInt();
  final tmdbId = info == null ? null : _num(info['tmdbId'])?.toInt();
  if (info == null || id == null || tmdbId == null) return null;
  final status = SeerrMediaStatus.parse(info['status']);
  return SeerrMediaInfo(
    id: id,
    tmdbId: tmdbId,
    tvdbId: _num(info['tvdbId'])?.toInt(),
    status: status,
    jellyfinMediaId: _str(info['jellyfinMediaId']),
    seasons: _seasonStatuses(info['seasons']),
    requests: [
      for (final r in _arr(info['requests']))
        ?mapSeerrRequest(
          r,
          mediaType: mediaType,
          tmdbId: tmdbId,
          mediaStatus: status,
        ),
    ],
  );
}

SeerrTitle? _title(Map<Object?, Object?> raw, SeerrMediaType mediaType) {
  final tmdbId = _num(raw['id'])?.toInt();
  final title =
      _str(raw['title']) ??
      _str(raw['name']) ??
      _str(raw['originalTitle']) ??
      _str(raw['originalName']);
  if (tmdbId == null || title == null) return null;
  final releaseDate = _str(raw['releaseDate']) ?? _str(raw['firstAirDate']);
  final vote = _num(raw['voteAverage'])?.toDouble();
  return SeerrTitle(
    tmdbId: tmdbId,
    mediaType: mediaType,
    title: title,
    year: yearOf(releaseDate),
    releaseDate: releaseDate,
    overview: _str(raw['overview']),
    posterPath: _str(raw['posterPath']),
    backdropPath: _str(raw['backdropPath']),
    voteAverage: vote == null || vote == 0 ? null : vote,
    mediaInfo: mapSeerrMediaInfo(raw['mediaInfo'], mediaType),
  );
}

/// A search or discover result: a [SeerrTitle], a [SeerrPerson], or (unknown
/// kinds) null.
Object? mapSeerrResult(Object? raw) {
  final result = _obj(raw);
  if (result == null) return null;
  final type = SeerrMediaType.parse(result['mediaType']);
  if (type != null) return _title(result, type);
  if (result['mediaType'] == 'person') {
    final tmdbId = _num(result['id'])?.toInt();
    final name = _str(result['name']);
    if (tmdbId == null || name == null) return null;
    return SeerrPerson(
      tmdbId: tmdbId,
      name: name,
      profilePath: _str(result['profilePath']),
      knownFor: [
        for (final k in _arr(result['knownFor']))
          if (mapSeerrResult(k) case final SeerrTitle t) t,
      ],
    );
  }
  return null;
}

SeerrSearchResults mapSeerrResults(Object? raw) {
  final page = _obj(raw);
  final results = [for (final r in _arr(page?['results'])) mapSeerrResult(r)];
  return SeerrSearchResults(
    page: _num(page?['page'])?.toInt() ?? 1,
    totalPages: _num(page?['totalPages'])?.toInt() ?? 1,
    totalResults: _num(page?['totalResults'])?.toInt() ?? results.length,
    titles: results.whereType<SeerrTitle>().toList(growable: false),
    people: results.whereType<SeerrPerson>().toList(growable: false),
  );
}

SeerrSeason? _season(Object? raw) {
  final season = _obj(raw);
  final number = season == null ? null : _num(season['seasonNumber'])?.toInt();
  if (season == null || number == null) return null;
  return SeerrSeason(
    seasonNumber: number,
    name: _str(season['name']) ?? 'Season $number',
    episodeCount: _num(season['episodeCount'])?.toInt() ?? 0,
    airDate: _str(season['airDate']),
    posterPath: _str(season['posterPath']),
    overview: _str(season['overview']),
  );
}

SeerrCastMember? _cast(Object? raw) {
  final member = _obj(raw);
  final id = member == null ? null : _num(member['id'])?.toInt();
  final name = member == null ? null : _str(member['name']);
  if (member == null || id == null || name == null) return null;
  return SeerrCastMember(
    id: id,
    name: name,
    character: _str(member['character']),
    profilePath: _str(member['profilePath']),
  );
}

/// The YouTube trailer TMDB lists first, if any.
String? _trailerUrl(Map<Object?, Object?> raw) {
  for (final video in _arr(raw['relatedVideos'])) {
    final entry = _obj(video);
    if (entry == null) continue;
    final url = _str(entry['url']);
    final type = _str(entry['type'])?.toLowerCase();
    if (url != null &&
        (type == 'trailer' || type == 'teaser') &&
        RegExp(r'youtube|youtu\.be').hasMatch(url)) {
      return url;
    }
  }
  return null;
}

String? _contentRating(Map<Object?, Object?> raw, SeerrMediaType type) {
  if (type == SeerrMediaType.movie) {
    for (final release in _arr(_obj(raw['releases'])?['results'])) {
      final entry = _obj(release);
      if (entry == null || entry['iso_3166_1'] != 'US') continue;
      for (final date in _arr(entry['release_dates'])) {
        final certification = _str(_obj(date)?['certification']);
        if (certification != null) return certification;
      }
    }
    return null;
  }
  for (final rating in _arr(_obj(raw['contentRatings'])?['results'])) {
    final entry = _obj(rating);
    if (entry != null && entry['iso_3166_1'] == 'US') {
      return _str(entry['rating']);
    }
  }
  return null;
}

SeerrDetails? mapSeerrDetails(Object? raw, SeerrMediaType mediaType) {
  final details = _obj(raw);
  final title = details == null ? null : _title(details, mediaType);
  if (details == null || title == null) return null;
  final externalIds = _obj(details['externalIds']);
  int? runtime;
  if (mediaType == SeerrMediaType.movie) {
    runtime = _num(details['runtime'])?.toInt();
  } else {
    for (final n in _arr(details['episodeRunTime'])) {
      final minutes = _num(n)?.toInt();
      if (minutes != null && minutes > 0) {
        runtime = minutes;
        break;
      }
    }
  }
  return SeerrDetails(
    tmdbId: title.tmdbId,
    mediaType: mediaType,
    title: title.title,
    year: title.year,
    releaseDate: title.releaseDate,
    overview: title.overview,
    posterPath: title.posterPath,
    backdropPath: title.backdropPath,
    voteAverage: title.voteAverage,
    mediaInfo: title.mediaInfo,
    tagline: _str(details['tagline']),
    runtime: runtime != null && runtime > 0 ? runtime : null,
    genres: [for (final g in _arr(details['genres'])) ?_str(_obj(g)?['name'])],
    status: mediaType == SeerrMediaType.tv ? _str(details['status']) : null,
    contentRating: _contentRating(details, mediaType),
    imdbId: _str(details['imdbId']) ?? _str(externalIds?['imdbId']),
    tvdbId: _num(externalIds?['tvdbId'])?.toInt() ?? title.mediaInfo?.tvdbId,
    seasons: [
      for (final s in _arr(details['seasons']))
        if (_season(s) case final season? when season.seasonNumber > 0) season,
    ],
    cast: [
      for (final c in _arr(_obj(details['credits'])?['cast'])) ?_cast(c),
    ].take(20).toList(growable: false),
    networks: [
      for (final n in _arr(details['networks'])) ?_str(_obj(n)?['name']),
    ],
    trailerUrl: _trailerUrl(details),
  );
}

SeerrStatus mapSeerrStatus(Object? raw) {
  final status = _obj(raw);
  final user = _obj(status?['user']);
  final userId = user == null ? null : _num(user['id'])?.toInt();
  return SeerrStatus(
    configured: status?['configured'] == true,
    reachable: status?['reachable'] == true,
    version: _str(status?['version']),
    user: user != null && userId != null
        ? SeerrUser(
            id: userId,
            displayName: _str(user['displayName']) ?? 'User $userId',
            permissions: _num(user['permissions'])?.toInt() ?? 0,
          )
        : null,
    error: _str(status?['error']),
  );
}

SeerrRequestsPage mapSeerrRequestsPage(Object? raw) {
  final page = _obj(raw);
  final info = _obj(page?['pageInfo']);
  final requests = [
    for (final r in _arr(page?['results'])) ?mapSeerrRequest(r),
  ];
  return SeerrRequestsPage(
    total: _num(info?['results'])?.toInt() ?? requests.length,
    pages: _num(info?['pages'])?.toInt() ?? 1,
    requests: requests,
  );
}

// ── labels ────────────────────────────────────────────────────────────────

enum AvailabilityTone { ok, partial, pending, declined }

/// Short label for where a title stands in the library, or null when it's
/// simply not there.
String? availabilityLabel(SeerrMediaInfo? info) => switch (info?.status) {
  SeerrMediaStatus.available => 'In your library',
  SeerrMediaStatus.partiallyAvailable => 'Partly in library',
  SeerrMediaStatus.processing => 'On its way',
  SeerrMediaStatus.pending => 'Requested',
  _ => null,
};

AvailabilityTone? availabilityTone(SeerrMediaInfo? info) =>
    switch (info?.status) {
      SeerrMediaStatus.available => AvailabilityTone.ok,
      SeerrMediaStatus.partiallyAvailable => AvailabilityTone.partial,
      SeerrMediaStatus.processing ||
      SeerrMediaStatus.pending => AvailabilityTone.pending,
      _ => null,
    };

bool isInLibrary(SeerrMediaInfo? info) =>
    info?.status == SeerrMediaStatus.available ||
    info?.status == SeerrMediaStatus.partiallyAvailable;

/// A season's own status when Seerr has it: in the library, or covered by a
/// request.
SeerrMediaStatus? seasonStatus(SeerrMediaInfo? info, int seasonNumber) {
  if (info == null) return null;
  for (final own in info.seasons) {
    if (own.seasonNumber == seasonNumber &&
        own.status != SeerrMediaStatus.unknown) {
      return own.status;
    }
  }
  for (final request in info.requests) {
    if (request.status == SeerrRequestStatus.declined ||
        request.status == SeerrRequestStatus.failed) {
      continue;
    }
    if (request.seasons.any((s) => s.seasonNumber == seasonNumber)) {
      return request.status == SeerrRequestStatus.pending
          ? SeerrMediaStatus.pending
          : SeerrMediaStatus.processing;
    }
  }
  return null;
}

/// Whether the title (or, for a show, every season) is already there or on
/// its way, so there's nothing left to request.
bool nothingToRequest(SeerrMediaInfo? info, List<SeerrSeason> seasons) {
  if (info == null) return false;
  if (info.status == SeerrMediaStatus.available) return true;
  if (seasons.isEmpty) {
    return info.status == SeerrMediaStatus.pending ||
        info.status == SeerrMediaStatus.processing;
  }
  return seasons.every((s) => seasonStatus(info, s.seasonNumber) != null);
}

String? seasonStatusLabel(SeerrMediaStatus? status) => switch (status) {
  SeerrMediaStatus.available => 'In library',
  SeerrMediaStatus.partiallyAvailable => 'Partly in library',
  SeerrMediaStatus.processing => 'On its way',
  SeerrMediaStatus.pending => 'Requested',
  _ => null,
};

/// What a request's row says about it.
({String label, AvailabilityTone tone}) requestStatusLabel(
  SeerrRequest request,
) => switch (request.status) {
  SeerrRequestStatus.declined => (
    label: 'Declined',
    tone: AvailabilityTone.declined,
  ),
  SeerrRequestStatus.failed => (
    label: 'Failed',
    tone: AvailabilityTone.declined,
  ),
  SeerrRequestStatus.pending => (
    label: 'Pending approval',
    tone: AvailabilityTone.pending,
  ),
  _ when request.mediaStatus == SeerrMediaStatus.available => (
    label: 'In your library',
    tone: AvailabilityTone.ok,
  ),
  _ when request.mediaStatus == SeerrMediaStatus.partiallyAvailable => (
    label: 'Partly in library',
    tone: AvailabilityTone.partial,
  ),
  _ => (label: 'Approved, on its way', tone: AvailabilityTone.pending),
};

/// "3 seasons", "Season 2", "Seasons 1, 3" — or null for a movie.
String? seasonsLabel(SeerrRequest request) {
  if (request.mediaType != SeerrMediaType.tv || request.seasons.isEmpty) {
    return null;
  }
  final numbers = request.seasons.map((s) => s.seasonNumber).toList()..sort();
  if (numbers.length == 1) return 'Season ${numbers.first}';
  if (numbers.length > 4) return '${numbers.length} seasons';
  return 'Seasons ${numbers.join(', ')}';
}

String? runtimeMinutesLabel(int? minutes) {
  if (minutes == null || minutes <= 0) return null;
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours == 0) return '${rest}m';
  return rest > 0 ? '${hours}h ${rest}m' : '${hours}h';
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "12 Mar 2026" for a request's date.
String? shortDate(DateTime? date) {
  if (date == null) return null;
  final local = date.toLocal();
  return '${local.day} ${_months[local.month - 1]} ${local.year}';
}

/// A TMDB image URL for a Seerr poster/backdrop/profile path. Paths that
/// are already URLs or bundled assets pass through.
String? tmdbImageUrl(String? path, TmdbImageKind kind) {
  if (path == null || path.isEmpty) return null;
  if (path.startsWith('http://') ||
      path.startsWith('https://') ||
      path.startsWith('assets/')) {
    return path;
  }
  final size = switch (kind) {
    TmdbImageKind.poster => 'w500',
    TmdbImageKind.backdrop => 'w1280',
    TmdbImageKind.profile => 'w185',
  };
  return 'https://image.tmdb.org/t/p/$size${path.startsWith('/') ? path : '/$path'}';
}

enum TmdbImageKind { poster, backdrop, profile }

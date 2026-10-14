/// Domain models mirroring apps/web/app/types/jellyfin.ts.
library;

class ImageRef {
  const ImageRef(this.itemId, this.type, this.tag);
  final String itemId;
  final String type; // Primary | Backdrop
  final String? tag;

  @override
  bool operator ==(Object other) =>
      other is ImageRef &&
      other.itemId == itemId &&
      other.type == type &&
      other.tag == tag;

  @override
  int get hashCode => Object.hash(itemId, type, tag);
}

class Person {
  const Person({
    required this.id,
    required this.name,
    this.role,
    this.type,
    this.primaryImageTag,
  });
  final String id;
  final String name;
  final String? role;
  final String? type;
  final String? primaryImageTag;

  ImageRef get image => ImageRef(id, 'Primary', primaryImageTag);

  static Person? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = '${raw['Id'] ?? ''}';
    final name = '${raw['Name'] ?? ''}';
    if (id.isEmpty || name.isEmpty) return null;
    final tags = raw['ImageTags'] is Map ? raw['ImageTags'] as Map : const {};
    final role = raw['Role'] as String?;
    return Person(
      id: id,
      name: name,
      role: role == null || role.isEmpty ? null : role,
      type: raw['Type'] as String?,
      primaryImageTag: (raw['PrimaryImageTag'] ?? tags['Primary']) as String?,
    );
  }
}

enum StreamKind { video, audio, subtitle }

class MediaStreamInfo {
  const MediaStreamInfo({
    required this.index,
    required this.kind,
    this.codec,
    this.language,
    this.displayTitle,
    this.isDefault = false,
    this.isExternal = false,
    this.isTextSubtitle = false,
    this.width,
    this.height,
  });
  final int index;
  final StreamKind kind;
  final String? codec;
  final String? language;
  final String? displayTitle;
  final bool isDefault;
  final bool isExternal;
  final bool isTextSubtitle;
  final int? width;
  final int? height;

  String get label => displayTitle ?? language ?? codec ?? 'Track $index';

  static const _textCodecs = {
    'srt',
    'subrip',
    'ass',
    'ssa',
    'vtt',
    'webvtt',
    'mov_text',
    'text',
    'ttml',
  };

  static MediaStreamInfo? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final kind = switch (raw['Type']) {
      'Video' => StreamKind.video,
      'Audio' => StreamKind.audio,
      'Subtitle' => StreamKind.subtitle,
      _ => null,
    };
    if (kind == null) return null;
    final codec = (raw['Codec'] as String?)?.toLowerCase();
    return MediaStreamInfo(
      index: (raw['Index'] as num?)?.toInt() ?? -1,
      kind: kind,
      codec: codec,
      language: raw['Language'] as String?,
      displayTitle: raw['DisplayTitle'] as String?,
      isDefault: raw['IsDefault'] == true,
      isExternal: raw['IsExternal'] == true,
      isTextSubtitle:
          kind == StreamKind.subtitle &&
          (raw['IsTextSubtitleStream'] == true ||
              (codec != null && _textCodecs.contains(codec))),
      width: (raw['Width'] as num?)?.toInt(),
      height: (raw['Height'] as num?)?.toInt(),
    );
  }
}

class Chapter {
  const Chapter({required this.name, required this.startTicks, this.imageTag});
  final String name;
  final int startTicks;
  final String? imageTag;
}

/// One cell of a [Trickplay] sprite sheet.
typedef TrickplayFrame = ({int sheet, int x, int y});

/// Seek-bar thumbnails Jellyfin (10.9+) tiles into JPEG sprite sheets at
/// `Videos/{id}/Trickplay/{width}/{sheet}.jpg`.
class Trickplay {
  const Trickplay({
    required this.width,
    required this.height,
    required this.tileWidth,
    required this.tileHeight,
    required this.thumbnailCount,
    required this.interval,
  });

  /// Thumbnail width; also the {width} in the sheet URL.
  final int width;
  final int height;

  /// Thumbnails per row and column of a sheet.
  final int tileWidth;
  final int tileHeight;
  final int thumbnailCount;

  /// Time between thumbnails.
  final Duration interval;

  /// Same target as the web player, which the server settings are tuned for.
  static const preferredWidth = 320;

  int get perSheet => tileWidth * tileHeight;
  int get sheetWidth => tileWidth * width;
  int get sheetHeight => tileHeight * height;

  TrickplayFrame frameAt(Duration position) {
    final n = (position.inMilliseconds ~/ interval.inMilliseconds).clamp(
      0,
      thumbnailCount - 1,
    );
    final local = n % perSheet;
    return (
      sheet: n ~/ perSheet,
      x: (local % tileWidth) * width,
      y: (local ~/ tileWidth) * height,
    );
  }

  static Trickplay? _fromJson(Object? raw) {
    if (raw is! Map) return null;
    int? n(String key) => (raw[key] as num?)?.toInt();
    final width = n('Width'), height = n('Height');
    final tileWidth = n('TileWidth'), tileHeight = n('TileHeight');
    final count = n('ThumbnailCount'), interval = n('Interval');
    if (width == null ||
        height == null ||
        tileWidth == null ||
        tileHeight == null ||
        count == null ||
        interval == null ||
        [
          width,
          height,
          tileWidth,
          tileHeight,
          count,
          interval,
        ].any((v) => v <= 0)) {
      return null;
    }
    return Trickplay(
      width: width,
      height: height,
      tileWidth: tileWidth,
      tileHeight: tileHeight,
      thumbnailCount: count,
      interval: Duration(milliseconds: interval),
    );
  }

  /// Reads an item's `Trickplay` field (media source id → width → info),
  /// keeping the width closest to [preferredWidth] for each source.
  static Map<String, Trickplay> parse(Object? raw) {
    if (raw is! Map) return const {};
    final result = <String, Trickplay>{};
    raw.forEach((sourceId, widths) {
      if (widths is! Map) return;
      Trickplay? best;
      for (final info in widths.values.map(_fromJson)) {
        if (info == null) continue;
        if (best == null ||
            (info.width - preferredWidth).abs() <
                (best.width - preferredWidth).abs()) {
          best = info;
        }
      }
      if (best != null) result['$sourceId'] = best;
    });
    return result;
  }
}

class RemoteTrailer {
  const RemoteTrailer({required this.url, this.name});
  final String url;
  final String? name;
}

class CatalogItem {
  const CatalogItem({
    required this.id,
    required this.name,
    required this.type,
    this.sortName,
    this.collectionType,
    this.overview,
    this.productionYear,
    this.communityRating,
    this.criticRating,
    this.officialRating,
    this.status,
    this.providerIds = const {},
    this.runTimeTicks,
    this.primaryImageTag,
    this.backdropImageTag,
    this.parentBackdropItemId,
    this.parentBackdropImageTag,
    this.logoImageTag,
    this.parentLogoItemId,
    this.parentLogoImageTag,
    this.seriesName,
    this.seriesPrimaryImageTag,
    this.seriesId,
    this.seasonId,
    this.indexNumber,
    this.parentIndexNumber,
    this.premiereDate,
    this.endDate,
    this.dateAdded,
    this.childCount,
    this.recursiveItemCount,
    this.genres = const [],
    this.studios = const [],
    this.tags = const [],
    this.people = const [],
    this.mediaSourceId,
    this.sourceBitrate,
    this.mediaStreams = const [],
    this.chapters = const [],
    this.trickplay = const {},
    this.remoteTrailers = const [],
    this.localTrailerCount,
    this.specialFeatureCount,
    this.extraType,
    this.isFavorite = false,
    this.played = false,
    this.playedPercentage,
    this.playbackPositionTicks = 0,
    this.lastPlayedDate,
  });

  final String id;
  final String name;
  final String type;
  final String? sortName;
  final String? collectionType;
  final String? overview;
  final int? productionYear;
  final double? communityRating;
  final double? criticRating;
  final String? officialRating;
  final String? status;
  final Map<String, String> providerIds;
  final int? runTimeTicks;
  final String? primaryImageTag;
  final String? backdropImageTag;
  final String? parentBackdropItemId;
  final String? parentBackdropImageTag;

  /// Transparent title art; episodes borrow their series' through the
  /// parent fields.
  final String? logoImageTag;
  final String? parentLogoItemId;
  final String? parentLogoImageTag;
  final String? seriesName;
  final String? seriesPrimaryImageTag;
  final String? seriesId;
  final String? seasonId;
  final int? indexNumber;
  final int? parentIndexNumber;
  final String? premiereDate;
  final String? endDate;

  /// When the item (or, for a series, its newest episode) reached the server.
  final DateTime? dateAdded;
  final int? childCount;
  final int? recursiveItemCount;
  final List<String> genres;
  final List<String> studios;
  final List<String> tags;
  final List<Person> people;
  final String? mediaSourceId;

  /// Total bitrate of the first media source in bits/s, when Jellyfin knows it.
  final int? sourceBitrate;
  final List<MediaStreamInfo> mediaStreams;
  final List<Chapter> chapters;

  /// Seek thumbnails per media source id; empty when the server made none.
  final Map<String, Trickplay> trickplay;
  final List<RemoteTrailer> remoteTrailers;
  final int? localTrailerCount;
  final int? specialFeatureCount;
  final String? extraType;
  final bool isFavorite;
  final bool played;
  final double? playedPercentage;
  final int playbackPositionTicks;

  /// When the user last played it (ISO 8601); null if never.
  final String? lastPlayedDate;

  CatalogItem copyWith({
    bool? isFavorite,
    bool? played,
    String? lastPlayedDate,
  }) => CatalogItem(
    id: id,
    name: name,
    type: type,
    sortName: sortName,
    collectionType: collectionType,
    overview: overview,
    productionYear: productionYear,
    communityRating: communityRating,
    criticRating: criticRating,
    officialRating: officialRating,
    status: status,
    providerIds: providerIds,
    runTimeTicks: runTimeTicks,
    primaryImageTag: primaryImageTag,
    backdropImageTag: backdropImageTag,
    parentBackdropItemId: parentBackdropItemId,
    parentBackdropImageTag: parentBackdropImageTag,
    logoImageTag: logoImageTag,
    parentLogoItemId: parentLogoItemId,
    parentLogoImageTag: parentLogoImageTag,
    seriesName: seriesName,
    seriesPrimaryImageTag: seriesPrimaryImageTag,
    seriesId: seriesId,
    seasonId: seasonId,
    indexNumber: indexNumber,
    parentIndexNumber: parentIndexNumber,
    premiereDate: premiereDate,
    endDate: endDate,
    dateAdded: dateAdded,
    childCount: childCount,
    recursiveItemCount: recursiveItemCount,
    genres: genres,
    studios: studios,
    tags: tags,
    people: people,
    mediaSourceId: mediaSourceId,
    sourceBitrate: sourceBitrate,
    mediaStreams: mediaStreams,
    chapters: chapters,
    trickplay: trickplay,
    remoteTrailers: remoteTrailers,
    localTrailerCount: localTrailerCount,
    specialFeatureCount: specialFeatureCount,
    extraType: extraType,
    isFavorite: isFavorite ?? this.isFavorite,
    played: played ?? this.played,
    playedPercentage: playedPercentage,
    playbackPositionTicks: playbackPositionTicks,
    lastPlayedDate: lastPlayedDate ?? this.lastPlayedDate,
  );

  /// 2:3 key art; episodes use their series poster instead of the still.
  ImageRef get poster {
    if (type == 'Episode' &&
        seriesId != null &&
        seriesPrimaryImageTag != null) {
      return ImageRef(seriesId!, 'Primary', seriesPrimaryImageTag);
    }
    return ImageRef(id, 'Primary', primaryImageTag);
  }

  /// 16:9 art: own backdrop, else parent's; episodes prefer their own still.
  ImageRef get landscape {
    if (type == 'Episode' && primaryImageTag != null) {
      return ImageRef(id, 'Primary', primaryImageTag);
    }
    return backdrop;
  }

  ImageRef get backdrop {
    if (backdropImageTag != null)
      return ImageRef(id, 'Backdrop', backdropImageTag);
    if (parentBackdropItemId != null) {
      return ImageRef(
        parentBackdropItemId!,
        'Backdrop',
        parentBackdropImageTag,
      );
    }
    return ImageRef(id, 'Backdrop', null);
  }

  /// Title art (own, else the series'), or null when there is none.
  ImageRef? get logo {
    if (logoImageTag != null) return ImageRef(id, 'Logo', logoImageTag);
    if (parentLogoItemId != null && parentLogoImageTag != null) {
      return ImageRef(parentLogoItemId!, 'Logo', parentLogoImageTag);
    }
    return null;
  }

  bool get hasBackdrop =>
      backdropImageTag != null ||
      (parentBackdropItemId != null && parentBackdropImageTag != null);

  bool get isPlayable =>
      type == 'Movie' ||
      type == 'Episode' ||
      type == 'Video' ||
      type == 'Trailer';

  /// Thumbnails for [sourceId] (the version playing), else for any version,
  /// with the source id their sheets are requested under.
  ({String sourceId, Trickplay info})? trickplayFor(String? sourceId) {
    final id = trickplay.containsKey(sourceId ?? mediaSourceId)
        ? (sourceId ?? mediaSourceId)!
        : trickplay.keys.firstOrNull;
    return id == null ? null : (sourceId: id, info: trickplay[id]!);
  }

  List<MediaStreamInfo> streamsOf(StreamKind kind) =>
      mediaStreams.where((s) => s.kind == kind).toList(growable: false);

  static List<String> _strings(Object? value) {
    if (value is! List) return const [];
    return [
      for (final entry in value)
        if (entry is String && entry.isNotEmpty)
          entry
        else if (entry is Map && '${entry['Name'] ?? ''}'.isNotEmpty)
          '${entry['Name']}',
    ];
  }

  static CatalogItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = '${raw['Id'] ?? ''}';
    final name = '${raw['Name'] ?? ''}';
    if (id.isEmpty || name.isEmpty) return null;
    final tags = raw['ImageTags'] is Map ? raw['ImageTags'] as Map : const {};
    final backdropTags = raw['BackdropImageTags'];
    final parentBackdropTags = raw['ParentBackdropImageTags'];
    final userData = raw['UserData'] is Map ? raw['UserData'] as Map : const {};
    final sources = raw['MediaSources'] is List
        ? raw['MediaSources'] as List
        : const [];
    final firstSource = sources.isNotEmpty && sources.first is Map
        ? sources.first as Map
        : null;
    final rawStreams = firstSource?['MediaStreams'] ?? raw['MediaStreams'];
    final providers = <String, String>{};
    if (raw['ProviderIds'] is Map) {
      (raw['ProviderIds'] as Map).forEach((k, v) {
        if (v is String && v.trim().isNotEmpty) providers['$k'] = v.trim();
      });
    }
    return CatalogItem(
      id: id,
      name: name,
      type: '${raw['Type'] ?? ''}',
      sortName: raw['SortName'] as String?,
      collectionType: raw['CollectionType'] as String?,
      overview: raw['Overview'] as String?,
      productionYear: (raw['ProductionYear'] as num?)?.toInt(),
      communityRating: (raw['CommunityRating'] as num?)?.toDouble(),
      criticRating: (raw['CriticRating'] as num?)?.toDouble(),
      officialRating: raw['OfficialRating'] as String?,
      status: raw['Status'] as String?,
      providerIds: providers,
      runTimeTicks: (raw['RunTimeTicks'] as num?)?.toInt(),
      primaryImageTag: tags['Primary'] as String?,
      backdropImageTag: backdropTags is List && backdropTags.isNotEmpty
          ? '${backdropTags.first}'
          : null,
      parentBackdropItemId: raw['ParentBackdropItemId'] as String?,
      parentBackdropImageTag:
          parentBackdropTags is List && parentBackdropTags.isNotEmpty
          ? '${parentBackdropTags.first}'
          : null,
      logoImageTag: tags['Logo'] as String?,
      parentLogoItemId: raw['ParentLogoItemId'] as String?,
      parentLogoImageTag: raw['ParentLogoImageTag'] as String?,
      seriesName: raw['SeriesName'] as String?,
      seriesPrimaryImageTag: raw['SeriesPrimaryImageTag'] as String?,
      seriesId: raw['SeriesId'] as String?,
      seasonId: raw['SeasonId'] as String?,
      indexNumber: (raw['IndexNumber'] as num?)?.toInt(),
      parentIndexNumber: (raw['ParentIndexNumber'] as num?)?.toInt(),
      premiereDate: raw['PremiereDate'] as String?,
      endDate: raw['EndDate'] as String?,
      dateAdded: DateTime.tryParse(
        (raw['DateLastMediaAdded'] ?? raw['DateCreated'] ?? '') as String,
      ),
      childCount: (raw['ChildCount'] as num?)?.toInt(),
      recursiveItemCount: (raw['RecursiveItemCount'] as num?)?.toInt(),
      genres: _strings(raw['Genres']),
      studios: _strings(raw['Studios']),
      tags: _strings(raw['Tags']),
      people: [
        if (raw['People'] is List)
          for (final p in raw['People'] as List) ?Person.fromJson(p),
      ],
      mediaSourceId: firstSource == null ? null : firstSource['Id'] as String?,
      sourceBitrate: switch (firstSource?['Bitrate']) {
        final num b when b > 0 => b.toInt(),
        _ => null,
      },
      mediaStreams: [
        if (rawStreams is List)
          for (final s in rawStreams) ?MediaStreamInfo.fromJson(s),
      ],
      chapters: [
        if (raw['Chapters'] is List)
          for (final c in raw['Chapters'] as List)
            if (c is Map && c['StartPositionTicks'] is num)
              Chapter(
                name: '${c['Name'] ?? ''}',
                startTicks: (c['StartPositionTicks'] as num).toInt(),
                imageTag: c['ImageTag'] as String?,
              ),
      ],
      trickplay: Trickplay.parse(raw['Trickplay']),
      remoteTrailers: [
        if (raw['RemoteTrailers'] is List)
          for (final t in raw['RemoteTrailers'] as List)
            if (t is Map &&
                t['Url'] is String &&
                (t['Url'] as String).isNotEmpty)
              RemoteTrailer(
                url: t['Url'] as String,
                name: t['Name'] as String?,
              ),
      ],
      localTrailerCount: (raw['LocalTrailerCount'] as num?)?.toInt(),
      specialFeatureCount: (raw['SpecialFeatureCount'] as num?)?.toInt(),
      extraType: raw['ExtraType'] as String?,
      isFavorite: userData['IsFavorite'] == true,
      played: userData['Played'] == true,
      playedPercentage: (userData['PlayedPercentage'] as num?)?.toDouble(),
      playbackPositionTicks:
          (userData['PlaybackPositionTicks'] as num?)?.toInt() ?? 0,
      lastPlayedDate: userData['LastPlayedDate'] as String?,
    );
  }
}

class Shelf {
  const Shelf({required this.title, required this.items, this.libraryId});
  final String title;
  final List<CatalogItem> items;
  final String? libraryId; // "See all" target
}

class HomeData {
  const HomeData({
    required this.resume,
    required this.nextUp,
    required this.recentlyAdded,
    this.keepWatching = const [],
    this.random = const [],
  });
  final List<CatalogItem> resume;
  final List<CatalogItem> nextUp;

  /// [resume] and [nextUp] merged, most recently watched show or film first.
  final List<CatalogItem> keepWatching;
  final List<Shelf> recentlyAdded;

  /// Random movies and shows with backdrops; fills out the hero.
  final List<CatalogItem> random;
}

class HomeExtras {
  const HomeExtras({
    this.topRated = const [],
    this.unwatchedTopRated = const [],
  });
  final List<CatalogItem> topRated;
  final List<CatalogItem> unwatchedTopRated;
}

class CuratedTheme {
  const CuratedTheme({
    required this.bg,
    required this.accent,
    required this.mid,
    required this.label,
  });
  final int bg;
  final int accent;
  final int mid;
  final int label;
}

class CuratedCollection {
  const CuratedCollection({
    required this.id,
    required this.title,
    required this.description,
    required this.items,
    required this.theme,
  });
  final String id;
  final String title;
  final String description;
  final List<CatalogItem> items;
  final CuratedTheme theme;

  int get itemCount => items.length;

  String get countLabel {
    final series = items.where((i) => i.type == 'Series').length;
    final movies = items.length - series;
    if (series > 0 && movies > 0) return '${items.length} titles';
    if (series > 0) return series == 1 ? '1 series' : '$series series';
    return movies == 1 ? '1 film' : '$movies films';
  }
}

/// Non-curated BoxSet fallback for the home spotlight.
class SpotlightCollection {
  const SpotlightCollection({required this.collection, required this.items});
  final CatalogItem collection;
  final List<CatalogItem> items;
}

class HomeCollection {
  const HomeCollection({this.curated = const [], this.spotlight});
  final List<CuratedCollection> curated;
  final SpotlightCollection? spotlight;
}

class SearchResults {
  const SearchResults({this.items = const [], this.people = const []});
  final List<CatalogItem> items;
  final List<Person> people;
}

class GenreCount {
  const GenreCount(this.name, this.count);
  final String name;
  final int count;
}

enum LibrarySort {
  title('SortName', 'Title'),
  recentlyAdded('DateCreated', 'Recently Added'),
  year('ProductionYear', 'Year'),
  rating('CommunityRating', 'Rating');

  const LibrarySort(this.apiValue, this.label);
  final String apiValue;
  final String label;

  bool get descending => this != title;
}

enum SegmentKind { intro, outro, recap, preview, commercial }

class MediaSegment {
  const MediaSegment(this.kind, this.startTicks, this.endTicks);
  final SegmentKind kind;
  final int startTicks;
  final int endTicks;
}

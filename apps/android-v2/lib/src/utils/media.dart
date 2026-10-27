import '../data/models.dart';
import '../data/playback_prefs.dart';

/// Ports of apps/web/app/utils/media.ts.
const _ticksPerMinute = 10000000 * 60;
const resumeThresholdTicks = 100000000;

String? runtimeLabel(int? ticks) {
  if (ticks == null || ticks == 0) return null;
  final total = (ticks / _ticksPerMinute).round().clamp(1, 1 << 30);
  final hours = total ~/ 60;
  final minutes = total % 60;
  if (hours == 0) return '$minutes min';
  return minutes > 0 ? '$hours hr $minutes min' : '$hours hr';
}

int? minutesLeft(CatalogItem item) {
  final position = item.playbackPositionTicks;
  final total = item.runTimeTicks;
  if (total == null || position < resumeThresholdTicks) return null;
  return ((total - position) / _ticksPerMinute).round().clamp(1, 1 << 30);
}

String? timeLeftLabel(CatalogItem item) {
  final left = minutesLeft(item);
  if (left == null) return null;
  if (left < 60) return '$left min left';
  final h = left ~/ 60;
  final m = left % 60;
  return m > 0 ? '$h hr $m min left' : '$h hr left';
}

String? episodeCode(CatalogItem item) {
  if (item.type != 'Episode') return null;
  final s = item.parentIndexNumber;
  final e = item.indexNumber;
  if (s != null && e != null) return 'Season $s, Episode $e';
  if (e != null) return 'Episode $e';
  return null;
}

bool canResume(CatalogItem item) =>
    item.isPlayable && item.playbackPositionTicks >= resumeThresholdTicks;

bool isInProgress(CatalogItem item) =>
    !item.played && (item.playedPercentage ?? 0) > 0;

String? yearLabel(CatalogItem item) {
  final year = item.productionYear;
  if (year == null) return null;
  if (item.type == 'Series' && item.endDate != null) {
    final end = DateTime.tryParse(item.endDate!)?.year;
    if (end != null && end != year) return '$year – $end';
  }
  return '$year';
}

/// Resolution class (1080, 720…) rather than raw height: cropped widescreen
/// is often e.g. 1280×536. Matches `resolutionClass` in web utils/media.ts.
int? resolutionClass(MediaStreamInfo? video) {
  final width = video?.width ?? 0;
  final height = video?.height ?? 0;
  if (width == 0 && height == 0) return null;
  if (width >= 3200 || height >= 1800) return 2160;
  if (width >= 1800 || height >= 1000) return 1080;
  if (width >= 1200 || height >= 700) return 720;
  if (width >= 960 || height >= 560) return 576;
  return 480;
}

String resolutionLabel(int height) => height >= 2160 ? '4K' : '${height}p';

/// 8234000 → "8.2 Mbps", 640000 → "640 kbps".
String bitrateLabel(int bitsPerSecond) {
  if (bitsPerSecond < 1000000) return '${(bitsPerSecond / 1000).round()} kbps';
  final mbps = (bitsPerSecond / 1000000).toStringAsFixed(1);
  return '${mbps.endsWith('.0') ? mbps.substring(0, mbps.length - 2) : mbps} Mbps';
}

/// The caps that would actually lower [item]'s quality: no taller than the
/// file and below its bitrate (a cap at or above it only forces a needless
/// transcode). Unknown values don't filter. See qualityCapsFor in media.ts.
List<({int bitrate, int height, String label, String detail})> qualityCapsFor(
  CatalogItem item,
) {
  final height = resolutionClass(item.streamsOf(StreamKind.video).firstOrNull);
  final bitrate = item.sourceBitrate;
  return [
    for (final q in PlaybackPrefs.qualityCaps)
      if ((height == null || q.height <= height) &&
          (bitrate == null || q.bitrate < bitrate))
        q,
  ];
}

List<String> qualityBadges(CatalogItem item) {
  final badges = <String>[];
  final video = item.mediaStreams
      .where((s) => s.kind == StreamKind.video)
      .firstOrNull;
  final width = video?.width;
  if (width != null) {
    badges.add(
      width >= 3200
          ? '4K'
          : width >= 1200
          ? 'HD'
          : 'SD',
    );
  }
  if (item.mediaStreams.any((s) => s.kind == StreamKind.subtitle)) {
    badges.add('CC');
  }
  return badges;
}

String initials(String name) => name
    .split(RegExp(r'\s+'))
    .where((p) => p.isNotEmpty)
    .take(2)
    .map((p) => p[0].toUpperCase())
    .join();

String sortTitle(CatalogItem item) => (item.sortName ?? item.name)
    .trim()
    .replaceFirst(RegExp(r'^(the|a|an)\s+', caseSensitive: false), '');

String sortLetter(CatalogItem item) {
  final t = sortTitle(item);
  if (t.isEmpty) return '#';
  final ch = t[0].toUpperCase();
  return RegExp(r'[A-Z]').hasMatch(ch) ? ch : '#';
}

List<GenreCount> countGenres(Iterable<CatalogItem> items) {
  final counts = <String, int>{};
  for (final item in items) {
    for (final g in item.genres) {
      counts[g] = (counts[g] ?? 0) + 1;
    }
  }
  final list = [for (final e in counts.entries) GenreCount(e.key, e.value)];
  list.sort((a, b) {
    final c = b.count.compareTo(a.count);
    return c != 0 ? c : a.name.compareTo(b.name);
  });
  return list;
}

/// Deterministic per-day shuffle (mulberry32 seeded by local date + salt).
List<T> dailyShuffle<T>(Iterable<T> items, [String salt = '', DateTime? now]) {
  now ??= DateTime.now();
  var seed = 0;
  for (final unit
      in '${now.year}-${now.month - 1}-${now.day}:$salt'.codeUnits) {
    seed = _i32(_imul(seed, 31) + unit);
  }
  double random() {
    seed = _i32(seed + 0x6D2B79F5);
    var t = _imul(seed ^ (seed & 0xFFFFFFFF) >>> 15, 1 | seed);
    t = _i32((t + _imul(t ^ (t & 0xFFFFFFFF) >>> 7, 61 | t)) ^ t);
    return (((t ^ (t & 0xFFFFFFFF) >>> 14) & 0xFFFFFFFF)) / 4294967296;
  }

  final copy = [...items];
  for (var i = copy.length - 1; i > 0; i--) {
    final j = (random() * (i + 1)).floor();
    final tmp = copy[i];
    copy[i] = copy[j];
    copy[j] = tmp;
  }
  return copy;
}

int _i32(int v) => v.toSigned(32);
int _imul(int a, int b) => ((a.toSigned(32) * b.toSigned(32))).toSigned(32);

/// One Keep Watching card per show; see collapseKeepWatching in media.ts.
({List<CatalogItem> resume, List<CatalogItem> nextUp}) collapseKeepWatching(
  List<CatalogItem> resume,
  List<CatalogItem> nextUp,
) {
  bool isEarlier(CatalogItem a, CatalogItem b) {
    final sa = a.parentIndexNumber ?? 0, sb = b.parentIndexNumber ?? 0;
    if (sa != sb) return sa < sb;
    return (a.indexNumber ?? 0) < (b.indexNumber ?? 0);
  }

  final collapsed = <CatalogItem>[];
  final slotBySeries = <String, int>{};
  for (final item in resume) {
    // Already watched, just with a saved position from a partial rewatch.
    if (item.played) continue;
    final seriesId = item.type == 'Episode' ? item.seriesId : null;
    if (seriesId == null) {
      collapsed.add(item);
      continue;
    }
    final slot = slotBySeries[seriesId];
    if (slot == null) {
      slotBySeries[seriesId] = collapsed.length;
      collapsed.add(item);
    } else if (isEarlier(item, collapsed[slot])) {
      collapsed[slot] = item;
    }
  }
  final seen = {for (final i in collapsed) i.seriesId ?? i.id};
  final next = <CatalogItem>[];
  for (final item in nextUp) {
    final key = item.seriesId ?? item.id;
    if (!seen.add(key)) continue;
    next.add(item);
  }
  return (resume: collapsed, nextUp: next);
}

/// A show's first episode isn't "up next" until it's started; Jellyfin 12
/// dropped the server-side DisableFirstEpisode option. See getHome in
/// useJellyfin.ts.
bool isFirstEpisode(CatalogItem item) =>
    item.parentIndexNumber == 1 && item.indexNumber == 1;

/// The Keep Watching row: [resume] and [nextUp] in one list, ordered by when
/// each show or film was last played; see orderKeepWatching in media.ts.
/// [activity] is everything with a play date (raw resume items and recently
/// played episodes), since a Next Up episode is usually unplayed. Items with
/// no known date keep their order, after the dated ones.
List<CatalogItem> orderKeepWatching(
  ({List<CatalogItem> resume, List<CatalogItem> nextUp}) home, [
  List<CatalogItem> activity = const [],
]) {
  int time(String? date) =>
      date == null ? 0 : DateTime.tryParse(date)?.millisecondsSinceEpoch ?? 0;
  final lastPlayedBySeries = <String, int>{};
  for (final item in activity) {
    final seriesId = item.seriesId;
    if (seriesId == null) continue;
    final played = time(item.lastPlayedDate);
    if (played > (lastPlayedBySeries[seriesId] ?? 0)) {
      lastPlayedBySeries[seriesId] = played;
    }
  }
  int lastActivity(CatalogItem item) {
    final own = time(item.lastPlayedDate);
    final show = item.seriesId == null
        ? 0
        : lastPlayedBySeries[item.seriesId] ?? 0;
    return own > show ? own : show;
  }

  final entries =
      [
        for (final (index, item) in [...home.resume, ...home.nextUp].indexed)
          (item: item, index: index, at: lastActivity(item)),
      ]..sort((a, b) {
        final byTime = b.at.compareTo(a.at);
        return byTime != 0 ? byTime : a.index.compareTo(b.index);
      });
  return [for (final e in entries) e.item];
}

/// Hero title size stepped down by length (see heroTitleClass).
double heroTitleSize(String title, double width) {
  final n = title.length;
  double clamp(double min, double vw, double max) =>
      (width * vw / 100).clamp(min, max);
  if (n <= 18) return clamp(44, 7.5, 104);
  if (n <= 30) return clamp(40, 6, 84);
  if (n <= 48) return clamp(36, 4.75, 64);
  return clamp(32, 3.75, 52);
}

/// The season a series page shows: the picked one, else the first numbered
/// season (so Specials don't lead), else the first.
CatalogItem pickSeason(List<CatalogItem> seasons, String? pickedId) =>
    seasons.firstWhere(
      (s) => s.id == pickedId,
      orElse: () => seasons.firstWhere(
        (s) => (s.indexNumber ?? 0) > 0,
        orElse: () => seasons.first,
      ),
    );

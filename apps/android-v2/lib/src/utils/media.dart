import '../data/models.dart';

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

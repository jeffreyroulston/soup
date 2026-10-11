import 'package:soup_core/soup_core.dart';

import '../../data/models.dart';

/// The soup_core item type [JellyfinApi] playback calls expect.
JellyfinItem toJellyfinItem(CatalogItem i) => JellyfinItem(
  id: i.id,
  name: i.name,
  type: i.type,
  overview: i.overview,
  productionYear: i.productionYear,
  runTimeTicks: i.runTimeTicks,
  playbackPositionTicks: i.playbackPositionTicks,
  seriesName: i.seriesName,
  indexNumber: i.indexNumber,
  parentIndexNumber: i.parentIndexNumber,
);

// ── languages (web utils/media.ts) ─────────────────────────────────────────
const _languageAliases = <String, List<String>>{
  'fre': ['fre', 'fra'],
  'ger': ['ger', 'deu'],
  'dut': ['dut', 'nld'],
  'chi': ['chi', 'zho'],
  'nor': ['nor', 'nob', 'nno'],
};

bool matchesLanguage(MediaStreamInfo stream, String language) {
  final code = stream.language?.toLowerCase();
  if (code == null || code.isEmpty) return false;
  return (_languageAliases[language] ?? [language]).contains(code);
}

MediaStreamInfo? defaultAudioStream(CatalogItem item) {
  final audio = item.streamsOf(StreamKind.audio);
  return audio.where((s) => s.isDefault).firstOrNull ?? audio.firstOrNull;
}

MediaStreamInfo? preferredAudioStream(CatalogItem item, String? language) {
  if (language == null) return null;
  final matches = item
      .streamsOf(StreamKind.audio)
      .where((s) => matchesLanguage(s, language))
      .toList();
  return matches.where((s) => s.isDefault).firstOrNull ?? matches.firstOrNull;
}

MediaStreamInfo? preferredSubtitleStream(CatalogItem item, String? language) {
  if (language == null) return null;
  final matches = item
      .streamsOf(StreamKind.subtitle)
      .where((s) => matchesLanguage(s, language))
      .toList();
  return matches.where((s) => s.isTextSubtitle && s.isDefault).firstOrNull ??
      matches.where((s) => s.isTextSubtitle).firstOrNull ??
      matches.firstOrNull;
}

// ── skip ranges (web utils/media.ts skipRanges) ────────────────────────────
enum SkipKind { intro, recap, preview, commercial, outro }

extension SkipKindLabel on SkipKind {
  String get label => switch (this) {
    SkipKind.intro => 'Skip intro',
    SkipKind.recap => 'Skip recap',
    SkipKind.preview => 'Skip preview',
    SkipKind.commercial => 'Skip ad',
    SkipKind.outro => 'Skip credits',
  };
}

class SkipRange {
  const SkipRange(this.start, this.end, this.kind);
  final double start; // seconds
  final double end;
  final SkipKind kind;

  bool contains(double seconds) => seconds >= start && seconds < end - 1;
}

final _introChapter = RegExp(
  r'^(?:intro(?:duction)?|opening(?: (?:credits|titles|theme|sequence))?|op|theme(?: song)?|title sequence|main titles)$',
  caseSensitive: false,
);
final _creditsChapter = RegExp(
  r'^(?:(?:end(?:ing)?|closing) (?:credits|titles)|credits|ending|outro|ed)$',
  caseSensitive: false,
);

double _seconds(int ticks) => ticks / 10000000;

String _chapterTitle(Chapter c) =>
    c.name.trim().replaceFirst(RegExp(r'^\d+\s*[.:\-–]\s*'), '');

({double start, double end})? _chapterRange(
  List<Chapter> sorted,
  RegExp pattern,
  double? fileEnd,
) {
  final index = sorted.indexWhere((c) => pattern.hasMatch(_chapterTitle(c)));
  if (index < 0) return null;
  final next = index + 1 < sorted.length ? sorted[index + 1] : null;
  final end = next != null ? _seconds(next.startTicks) : fileEnd;
  if (end == null) return null;
  return (start: _seconds(sorted[index].startTicks), end: end);
}

List<SkipRange> skipRanges(
  List<MediaSegment> segments,
  List<Chapter> chapters, {
  double? durationSeconds,
}) {
  const kinds = {
    SegmentKind.intro: SkipKind.intro,
    SegmentKind.outro: SkipKind.outro,
    SegmentKind.recap: SkipKind.recap,
    SegmentKind.preview: SkipKind.preview,
    SegmentKind.commercial: SkipKind.commercial,
  };
  final ranges = <SkipRange>[
    for (final s in segments)
      if (s.endTicks > s.startTicks)
        SkipRange(_seconds(s.startTicks), _seconds(s.endTicks), kinds[s.kind]!),
  ];
  final sorted = [...chapters]
    ..sort((a, b) => a.startTicks.compareTo(b.startTicks));
  if (!ranges.any((r) => r.kind == SkipKind.intro)) {
    final intro = _chapterRange(sorted, _introChapter, null);
    final length = intro == null ? 0 : intro.end - intro.start;
    if (intro != null && length >= 5 && length <= 180) {
      ranges.add(SkipRange(intro.start, intro.end, SkipKind.intro));
    }
  }
  if (!ranges.any((r) => r.kind == SkipKind.outro)) {
    final duration = (durationSeconds ?? 0) > 0 ? durationSeconds : null;
    final credits = _chapterRange(sorted, _creditsChapter, duration);
    final length = credits == null ? 0 : credits.end - credits.start;
    final late =
        credits != null && duration != null && credits.start >= duration / 2;
    if (credits != null && late && length >= 5 && length <= 15 * 60) {
      ranges.add(SkipRange(credits.start, credits.end, SkipKind.outro));
    }
  }
  ranges.sort((a, b) => a.start.compareTo(b.start));
  return ranges;
}

// ── transcode URL ──────────────────────────────────────────────────────────
/// HLS master playlist for forced transcoding when the plan has none (Jellyfin
/// omits `TranscodingUrl` when direct play is possible).
Uri manualTranscodeUri(
  JellyfinApi api,
  JellyfinSession session,
  JellyfinPlaybackPlan plan,
) {
  final relative = Uri(
    path: 'Videos/${plan.itemId}/master.m3u8',
    queryParameters: {
      'MediaSourceId': plan.mediaSourceId,
      'PlaySessionId': plan.playSessionId,
      'DeviceId': api.deviceId,
      'VideoCodec': 'h264',
      'AudioCodec': 'aac',
      'TranscodingMaxAudioChannels': '6',
      'SegmentContainer': 'ts',
      'MinSegments': '1',
      'BreakOnNonKeyFrames': 'true',
      'RequireAvc': 'false',
    },
  );
  return api.resolvePlaybackUri(session, relative.toString());
}

/// Applies the user's audio-track / quality choices to a transcode URL.
Uri withTranscodeOptions(Uri uri, {int? audioIndex, int? maxBitrate}) {
  final query = {...uri.queryParameters};
  if (audioIndex != null) query['AudioStreamIndex'] = '$audioIndex';
  if (maxBitrate != null) {
    query['MaxStreamingBitrate'] = '$maxBitrate';
    query['VideoBitrate'] = '${(maxBitrate * 0.9).round()}';
  }
  return uri.replace(queryParameters: query);
}

String formatTime(Duration value) {
  final h = value.inHours;
  final m = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h == 0 ? '$m:$s' : '$h:$m:$s';
}

String episodeCodeOf(CatalogItem item) {
  final s = item.parentIndexNumber;
  final e = item.indexNumber;
  if (s != null && e != null) return 'Season $s, Episode $e';
  if (e != null) return 'Episode $e';
  return '';
}

import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../data/models.dart';
import '../../navigation.dart';
import '../../ui/theme/soup_tokens.dart';
import '../../ui/widgets/catalog_builder.dart';
import '../../ui/widgets/catalog_image.dart';
import '../../ui/widgets/focusable.dart';
import '../../ui/widgets/select_menu.dart';
import '../../utils/media.dart';
import '../playback/playback_logic.dart';

// Pieces of the episode page shared by the TV and touch item screens (web
// `pages/item/[id].vue`): the still, track pickers, prev/next and the show card.

/// "Season 1 · Episode 4" above an episode's title.
String? episodeLabel(CatalogItem item) {
  final parts = [
    if (item.parentIndexNumber != null) 'Season ${item.parentIndexNumber}',
    if (item.indexNumber != null) 'Episode ${item.indexNumber}',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

const _shortMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const _longMonths = [
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// Air dates are stored as UTC midnight; read them in UTC so they don't
/// land on the day before.
String? airDate(CatalogItem item, {bool long = false}) {
  final raw = item.premiereDate;
  final date = raw == null ? null : DateTime.tryParse(raw)?.toUtc();
  if (date == null) return null;
  final month = (long ? _longMonths : _shortMonths)[date.month - 1];
  return '${date.day} $month ${date.year}';
}

/// An episode's title steps down as it gets longer, so it fits beside the
/// still; (font size, line height). Matches `episodeTitleClass` on the web.
(double, double) episodeTitleSize(String title, {bool touch = false}) {
  final length = title.length;
  if (length <= 20) return (touch ? 34 : 52, 1.0);
  if (length <= 40) return (touch ? 30 : 42, 1.05);
  return (touch ? 26 : 34, 1.1);
}

/// Aired date, runtime and rating under an episode's title.
List<String> episodeMeta(CatalogItem item) => [
  if (airDate(item) case final aired?) 'Aired $aired',
  ?runtimeLabel(item.runTimeTicks),
  if (item.communityRating != null)
    '★ ${item.communityRating!.toStringAsFixed(1)}',
];

/// Who directed and wrote the episode.
List<(String, String)> episodeCredits(CatalogItem item) {
  String names(String type) => {
    for (final p in item.people)
      if (p.type == type) p.name,
  }.join(', ');
  return [
    if (names('Director') case final d when d.isNotEmpty) ('Director', d),
    if (names('Writer') case final w when w.isNotEmpty) ('Writer', w),
  ];
}

/// Episode "Information": when it aired and what the file holds.
List<(String, String)> episodeInformation(CatalogItem item) {
  final video = item.streamsOf(StreamKind.video).firstOrNull;
  final height = resolutionClass(video);
  final videoLabel = [
    if (height != null) resolutionLabel(height),
    if (video?.codec case final codec?) codec.toUpperCase(),
  ].join(' · ');
  final audio = item.streamsOf(StreamKind.audio).map((s) => s.label);
  final subs = item.streamsOf(StreamKind.subtitle).map((s) => s.label);
  return [
    if (airDate(item, long: true) case final aired?) ('Aired', aired),
    if (runtimeLabel(item.runTimeTicks) case final runtime?)
      ('Runtime', runtime),
    if (videoLabel.isNotEmpty) ('Video', videoLabel),
    if (item.sourceBitrate case final bitrate?)
      ('Bitrate', bitrateLabel(bitrate)),
    if (audio.isNotEmpty) ('Audio', audio.join('\n')),
    if (subs.isNotEmpty) ('Subtitles', subs.join(', ')),
  ];
}

/// Auto plus the caps that would lower the file's quality, as in the player.
/// Empty when the item has no video stream.
List<SelectOption<int?>> qualityOptions(CatalogItem item) {
  final video = item.streamsOf(StreamKind.video).firstOrNull;
  if (video == null) return const [];
  final source = resolutionClass(video);
  return [
    SelectOption(
      null,
      source == null ? 'Auto' : 'Auto · ${resolutionLabel(source)}',
    ),
    for (final q in qualityCapsFor(item))
      SelectOption(q.bitrate, '${q.label} · ${q.detail}'),
  ];
}

/// Audio, subtitle and quality pickers. Audio and subtitles always show what
/// the file has; a lone audio track is a plain label, not a one-item menu.
class TrackPickers extends StatelessWidget {
  const TrackPickers({
    required this.item,
    required this.audio,
    required this.subtitle,
    required this.quality,
    required this.onAudio,
    required this.onSubtitle,
    required this.onQuality,
    this.surface = true,
    this.spacing = 12,
    super.key,
  });

  final CatalogItem item;

  /// null = default track.
  final int? audio;

  /// null = per settings, -1 = off.
  final int? subtitle;

  /// Bitrate cap; null = Auto.
  final int? quality;
  final ValueChanged<int?> onAudio;
  final ValueChanged<int?> onSubtitle;
  final ValueChanged<int?> onQuality;
  final bool surface;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final audioStreams = item.streamsOf(StreamKind.audio);
    final subs = item.streamsOf(StreamKind.subtitle);
    // With nothing picked, show the tracks playback will actually use (the
    // language settings, else the file's default), as the player resolves
    // them.
    final prefs = SoupScope.of(context).prefs;
    final audioValue =
        audio ??
        (preferredAudioStream(item, prefs.audioLanguage) ??
                defaultAudioStream(item))
            ?.index;
    final subtitleValue =
        subtitle ??
        preferredSubtitleStream(item, prefs.subtitleLanguage)?.index ??
        -1;
    final qualities = qualityOptions(item);
    if (audioStreams.isEmpty && subs.isEmpty && qualities.isEmpty) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      children: [
        if (audioStreams.length > 1)
          SelectMenu<int?>(
            icon: Icons.volume_up_rounded,
            surface: surface,
            value: audioValue,
            options: [
              for (final a in audioStreams) SelectOption(a.index, a.label),
            ],
            onChanged: onAudio,
          )
        else if (audioStreams.length == 1)
          _StaticPill(
            icon: Icons.volume_up_rounded,
            label: audioStreams.single.label,
            semanticsLabel: 'Audio: ${audioStreams.single.label}',
            surface: surface,
          ),
        if (subs.isNotEmpty)
          SelectMenu<int?>(
            icon: Icons.subtitles_outlined,
            surface: surface,
            value: subtitleValue,
            options: [
              const SelectOption(-1, 'Subtitles off'),
              for (final s in subs) SelectOption(s.index, s.label),
            ],
            onChanged: onSubtitle,
          )
        else if (audioStreams.isNotEmpty)
          _StaticPill(
            icon: Icons.subtitles_outlined,
            label: 'No subtitles',
            surface: surface,
            muted: true,
          ),
        if (qualities.isNotEmpty)
          SelectMenu<int?>(
            icon: Icons.hd_outlined,
            surface: surface,
            value: quality,
            options: qualities,
            onChanged: onQuality,
          ),
      ],
    );
  }
}

/// Looks like a [SelectMenu] trigger without the chevron; not focusable.
class _StaticPill extends StatelessWidget {
  const _StaticPill({
    required this.icon,
    required this.label,
    required this.surface,
    this.semanticsLabel,
    this.muted = false,
  });
  final IconData icon;
  final String label;
  final String? semanticsLabel;
  final bool surface;
  final bool muted;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticsLabel ?? label,
    child: ExcludeSemantics(
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: surface ? SoupColors.surface : const Color(0x99282828),
          borderRadius: BorderRadius.circular(23),
          border: Border.all(color: const Color(0x1AFFFFFF)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: muted ? SoupColors.muted : SoupColors.ink,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: SoupType.style(
                size: 15,
                weight: 700,
                color: muted ? SoupColors.muted : SoupColors.ink,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The episode's own still (the show's backdrop when it has none), with a
/// play badge and progress bar.
class EpisodeStill extends StatelessWidget {
  const EpisodeStill({required this.item, this.radius = 18, super.key});
  final CatalogItem item;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final progress = isInProgress(item)
        ? ((item.playedPercentage ?? 0) / 100).clamp(0.0, 1.0)
        : 0.0;
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: const Color(0x1AFFFFFF)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CatalogImage(
                image: item.landscape,
                maxWidth: 1280,
                fallbackTitle: item.name,
              ),
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0x99282828),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0x2EFFFFFF)),
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    size: 40,
                    color: SoupColors.ink,
                  ),
                ),
              ),
              if (progress > 0)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 5,
                      color: SoupColors.accent,
                      backgroundColor: const Color(0x4DFFFFFF),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Director / Writer lines under the overview.
class EpisodeCredits extends StatelessWidget {
  const EpisodeCredits({required this.item, this.size = 14, super.key});
  final CatalogItem item;
  final double size;

  @override
  Widget build(BuildContext context) {
    final credits = episodeCredits(item);
    if (credits.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.only(top: 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: SoupColors.elevated)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (label, value) in credits)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: size * 6.4,
                    child: Text(
                      label,
                      style: SoupType.style(size: size, weight: 800),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      value,
                      style: SoupType.style(
                        size: size,
                        color: SoupColors.muted,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Previous and next episode in the season, side by side.
class AdjacentEpisodes extends StatelessWidget {
  const AdjacentEpisodes({
    required this.item,
    this.thumbnails = true,
    super.key,
  });
  final CatalogItem item;
  final bool thumbnails;

  @override
  Widget build(BuildContext context) {
    final seriesId = item.seriesId;
    final seasonId = item.seasonId;
    if (seriesId == null || seasonId == null) return const SizedBox.shrink();
    return CatalogBuilder<List<CatalogItem>>(
      load: (c) => c.episodes(seriesId, seasonId),
      keys: [seriesId, seasonId],
      builder: (context, episodes, _) {
        final list = episodes ?? const <CatalogItem>[];
        final index = list.indexWhere((e) => e.id == item.id);
        if (index < 0) return const SizedBox.shrink();
        final previous = index > 0 ? list[index - 1] : null;
        final next = index + 1 < list.length ? list[index + 1] : null;
        if (previous == null && next == null) return const SizedBox.shrink();
        return Row(
          children: [
            Expanded(
              child: previous == null
                  ? const SizedBox.shrink()
                  : _AdjacentCard(
                      episode: previous,
                      label: 'Previous',
                      thumbnail: thumbnails,
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: next == null
                  ? const SizedBox.shrink()
                  : _AdjacentCard(
                      episode: next,
                      label: 'Next',
                      thumbnail: thumbnails,
                      trailing: true,
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _AdjacentCard extends StatelessWidget {
  const _AdjacentCard({
    required this.episode,
    required this.label,
    required this.thumbnail,
    this.trailing = false,
  });
  final CatalogItem episode;
  final String label;
  final bool thumbnail;
  final bool trailing;

  @override
  Widget build(BuildContext context) {
    final kicker = episode.indexNumber == null
        ? label.toUpperCase()
        : '${label.toUpperCase()} · E${episode.indexNumber}';
    final text = Expanded(
      child: Column(
        crossAxisAlignment: trailing
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            kicker,
            style: SoupType.style(
              size: 12,
              weight: 800,
              color: SoupColors.muted,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            episode.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SoupType.style(size: 15, weight: 800),
          ),
        ],
      ),
    );
    final thumb = thumbnail
        ? ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 80,
              height: 45,
              child: CatalogImage(
                image: episode.landscape,
                maxWidth: 240,
                fallbackTitle: '',
              ),
            ),
          )
        : null;
    final chevron = Icon(
      trailing ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
      size: 22,
      color: SoupColors.muted,
    );
    return Semantics(
      button: true,
      label: '$label episode: ${episode.name}',
      child: Focusable(
        radius: 14,
        scale: 1.02,
        onActivate: () => openItem(context, episode),
        builder: (context, focused) => Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: focused ? SoupColors.elevated : SoupColors.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: ExcludeSemantics(
            child: Row(
              children: trailing
                  ? [
                      text,
                      if (thumb != null) ...[const SizedBox(width: 12), thumb],
                      const SizedBox(width: 8),
                      chevron,
                    ]
                  : [
                      chevron,
                      const SizedBox(width: 8),
                      if (thumb != null) ...[thumb, const SizedBox(width: 12)],
                      text,
                    ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "From the show": poster, a line about the series, its main cast and a
/// way there. Stacks when narrow.
class ShowCard extends StatelessWidget {
  const ShowCard({required this.item, super.key});
  final CatalogItem item;

  @override
  Widget build(BuildContext context) {
    final seriesId = item.seriesId;
    if (seriesId == null) return const SizedBox.shrink();
    return CatalogBuilder<CatalogItem>(
      load: (c) => c.item(seriesId),
      keys: [seriesId],
      builder: (context, series, _) =>
          series == null ? const SizedBox.shrink() : _card(context, series),
    );
  }

  Widget _card(BuildContext context, CatalogItem series) {
    final meta = [
      'Series',
      ?yearLabel(series),
      if (series.genres.isNotEmpty) series.genres.take(2).join(', '),
    ].join(' · ');
    final cast = series.people.where((p) => p.type == 'Actor').take(3).toList();
    final about = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 96,
            height: 144,
            child: CatalogImage(
              image: series.poster,
              maxWidth: 320,
              fallbackTitle: series.name,
              fallbackFontSize: 14,
            ),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'FROM THE SHOW',
                style: SoupType.style(
                  size: 13,
                  weight: 800,
                  color: SoupColors.muted,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                series.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: SoupType.style(
                  size: 22,
                  weight: 800,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                meta,
                style: SoupType.style(
                  size: 14,
                  weight: 600,
                  color: SoupColors.muted,
                ),
              ),
              if (series.overview case final overview?
                  when overview.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  overview,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: SoupType.style(
                    size: 14,
                    color: SoupColors.ink2,
                    height: 1.45,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
    final castList = Wrap(
      spacing: 24,
      runSpacing: 14,
      children: [
        for (final p in cast)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipOval(
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: CatalogImage(
                    image: p.image,
                    maxWidth: 120,
                    fallbackTitle: initials(p.name),
                    fallbackFontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(p.name, style: SoupType.style(size: 14, weight: 700)),
                  if (p.role case final role? when role.isNotEmpty)
                    Text(
                      role,
                      style: SoupType.style(size: 13, color: SoupColors.muted),
                    ),
                ],
              ),
            ],
          ),
      ],
    );
    final goToShow = Focusable(
      radius: 22,
      onActivate: () => openItem(context, series),
      builder: (context, focused) => Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: focused ? const Color(0xFF3A3A3C) : SoupColors.elevated,
          borderRadius: BorderRadius.circular(23),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Go to show', style: SoupType.style(size: 15, weight: 800)),
            const SizedBox(width: 6),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: SoupColors.ink,
            ),
          ],
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0x991C1C1E),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SoupColors.elevated),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 900) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                about,
                if (cast.isNotEmpty) ...[const SizedBox(height: 20), castList],
                const SizedBox(height: 20),
                goToShow,
              ],
            );
          }
          return Row(
            children: [
              Expanded(flex: 5, child: about),
              const SizedBox(width: 40),
              if (cast.isNotEmpty) Expanded(flex: 4, child: castList),
              const SizedBox(width: 24),
              goToShow,
            ],
          );
        },
      ),
    );
  }
}

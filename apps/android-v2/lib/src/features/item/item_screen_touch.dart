import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../data/models.dart';
import '../../navigation.dart';
import '../../ui/theme/soup_tokens.dart';
import '../../ui/touch/touch_scaffold.dart';
import '../../ui/touch/touch_widgets.dart';
import '../../ui/widgets/action_menu.dart';
import '../../ui/widgets/catalog_builder.dart';
import '../../ui/widgets/catalog_image.dart';
import '../../ui/widgets/focusable.dart';
import '../../ui/widgets/glass_nav.dart' show NavSection;
import '../../ui/widgets/hero_carousel.dart' show ArtScrims;
import '../../ui/widgets/media_card.dart';
import '../../ui/widgets/meta_line.dart';
import '../../ui/widgets/person_card.dart';
import '../../ui/widgets/pill_tabs.dart';
import '../../ui/widgets/play_button.dart';
import '../../ui/widgets/title_art.dart';
import '../../ui/widgets/expandable_overview.dart';
import '../../ui/widgets/error_state.dart';
import '../../utils/media.dart';
import 'episode_parts.dart';
import 'item_screen.dart';

/// Touch item page: artwork header, then one column of actions, overview,
/// episodes, extras, cast, information and related titles. An episode leads
/// with its own still and keeps the show to a small card.
class TouchItemScreen extends StatefulWidget {
  const TouchItemScreen({required this.itemId, super.key});
  final String itemId;

  @override
  State<TouchItemScreen> createState() => _TouchItemScreenState();
}

class _TouchItemScreenState extends State<TouchItemScreen> {
  int? _audio; // null = default
  int? _subtitle; // null = per settings, -1 = off
  String? _seasonId;
  int? _quality; // bitrate cap, null = Auto; only once picked here
  bool _qualityPicked = false;

  /// The picked cap, else the one Settings prefers.
  int? get _effectiveQuality =>
      _qualityPicked ? _quality : SoupScope.of(context).prefs.maxBitrate;

  @override
  Widget build(BuildContext context) {
    return CatalogBuilder<CatalogItem>(
      load: (c) => c.item(widget.itemId),
      keys: [widget.itemId],
      builder: (context, item, error) {
        if (item == null) {
          return TouchScaffold(
            section: NavSection.none,
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: error != null
                      ? ErrorState(error: error)
                      : const CircularProgressIndicator(
                          color: SoupColors.accent,
                        ),
                ),
              ),
            ],
          );
        }
        final isEpisode = item.type == 'Episode';
        return TouchScaffold(
          section: NavSection.none,
          // An episode's still sits below the bar, and its title right under it.
          title: isEpisode ? null : item.name,
          overlayTopBar: !isEpisode,
          slivers: [
            SliverToBoxAdapter(
              child: isEpisode
                  ? _EpisodeHeader(item: item)
                  : _Header(item: item),
            ),
            SliverToBoxAdapter(child: _summary(context, item)),
            SliverToBoxAdapter(child: _body(item)),
          ],
        );
      },
    );
  }

  Widget _gap(Widget child) => Padding(
    padding: const EdgeInsets.only(top: TouchSpacing.rowGap),
    child: child,
  );

  Widget _summary(BuildContext context, CatalogItem item) {
    final isEpisode = item.type == 'Episode';
    // Pickers only apply when Play starts this item (not a series' episode).
    final tracks = item.isPlayable && item.mediaStreams.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: TouchSpacing.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          _Actions(
            item: item,
            audio: _audio,
            subtitle: _subtitle,
            quality: _effectiveQuality,
            seasonId: _seasonId,
          ),
          if (tracks) ...[
            const SizedBox(height: 14),
            TrackPickers(
              item: item,
              audio: _audio,
              subtitle: _subtitle,
              quality: _effectiveQuality,
              onAudio: (v) => setState(() => _audio = v),
              onSubtitle: (v) => setState(() => _subtitle = v),
              onQuality: (v) => setState(() {
                _quality = v;
                _qualityPicked = true;
              }),
              surface: isEpisode,
              spacing: 10,
            ),
          ],
          if (item.overview != null && item.overview!.isNotEmpty) ...[
            const SizedBox(height: 18),
            ExpandableOverview(
              text: item.overview!,
              maxLines: isEpisode ? 4 : 6,
              style: SoupType.style(
                size: 15,
                color: SoupColors.ink2,
                height: 1.45,
              ),
            ),
          ],
          if (isEpisode) ...[
            const SizedBox(height: 18),
            EpisodeCredits(item: item, size: 13),
            const SizedBox(height: 10),
            AdjacentEpisodes(item: item, thumbnails: false),
          ],
        ],
      ),
    );
  }

  Widget _body(CatalogItem item) => item.type == 'Episode'
      // The show stays a small card; no cast rail or Related for one episode.
      ? Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _gap(
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: TouchSpacing.gutter,
                ),
                child: ShowCard(item: item),
              ),
            ),
            _gap(_Information(item: item)),
          ],
        )
      : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.type == 'Series')
              _gap(
                _Episodes(
                  series: item,
                  seasonId: _seasonId,
                  onSeason: (id) => setState(() => _seasonId = id),
                ),
              ),
            if (item.type == 'BoxSet')
              CatalogBuilder<List<CatalogItem>>(
                load: (c) => c.children(item.id),
                keys: [item.id],
                builder: (context, children, _) => _gap(
                  TouchRow(
                    title: 'In This Collection',
                    items: children ?? const [],
                    loading: children == null,
                  ),
                ),
              ),
            CatalogBuilder<List<CatalogItem>>(
              load: (c) => c.extras(item),
              keys: [item.id],
              builder: (context, extras, _) => extras == null || extras.isEmpty
                  ? const SizedBox.shrink()
                  : _gap(
                      TouchRow(
                        title: 'Extras',
                        items: extras,
                        shape: CardShape.landscape,
                        cardBuilder: (context, e, _) => MediaCard(
                          item: e,
                          shape: CardShape.landscape,
                          width: TouchSpacing.landscapeWidth,
                          kicker: extraLabel(e),
                          onTap: () => openWatch(context, e, fromStart: true),
                        ),
                      ),
                    ),
            ),
            if (item.people.isNotEmpty) _gap(_Cast(people: item.people)),
            _gap(_Information(item: item)),
            if (item.type != 'BoxSet')
              CatalogBuilder<List<CatalogItem>>(
                load: (c) => c.similar(item.id),
                keys: [item.id],
                builder: (context, similar, _) =>
                    similar == null || similar.isEmpty
                    ? const SizedBox.shrink()
                    : _gap(TouchRow(title: 'Related', items: similar)),
              ),
          ],
        );
}

/// The episode's still, then "Season · Episode", its title and meta.
class _EpisodeHeader extends StatelessWidget {
  const _EpisodeHeader({required this.item});
  final CatalogItem item;

  @override
  Widget build(BuildContext context) {
    final label = episodeLabel(item);
    final chips = <String>[?item.officialRating, ...qualityBadges(item)];
    final (titleSize, titleHeight) = episodeTitleSize(item.name, touch: true);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        TouchSpacing.gutter,
        4,
        TouchSpacing.gutter,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EpisodeStill(item: item, radius: 14),
          const SizedBox(height: 18),
          if (label != null) ...[
            Text(
              label.toUpperCase(),
              style: SoupType.style(
                size: 13,
                weight: 800,
                color: SoupColors.accent,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 6),
          ],
          Text(
            item.name,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: SoupType.style(
              size: titleSize,
              weight: 800,
              letterSpacing: -1,
              height: titleHeight,
            ),
          ),
          const SizedBox(height: 10),
          MetaLine(
            bits: episodeMeta(item),
            chips: chips,
            size: 13,
            spacing: 14,
            color: SoupColors.muted,
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.item});
  final CatalogItem item;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isEpisode = item.type == 'Episode';
    final episodeLine = isEpisode
        ? [?item.seriesName, ?episodeCode(item)].join(', ')
        : null;
    final meta = <String>[
      ?yearLabel(item),
      ?runtimeLabel(item.runTimeTicks),
      ...item.genres.take(2),
      if (item.communityRating != null)
        '★ ${item.communityRating!.toStringAsFixed(1)}',
    ];
    final chips = <String>[?item.officialRating, ...qualityBadges(item)];
    return SizedBox(
      height: (width * 0.9).clamp(320.0, 520.0),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CatalogImage(
            image: item.hasBackdrop ? item.backdrop : item.poster,
            maxWidth: 1280,
            alignment: Alignment.topCenter,
            fallbackTitle: item.name,
          ),
          const ArtScrims(),
          Positioned(
            left: TouchSpacing.gutter,
            right: TouchSpacing.gutter,
            bottom: 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (episodeLine != null) ...[
                  Text(
                    episodeLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SoupType.style(
                      size: 14,
                      weight: 700,
                      color: SoupColors.ink2,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                TitleArt(
                  // Episodes keep the text: the show's logo would read as
                  // the show rather than this episode.
                  logo: isEpisode ? null : item.logo,
                  maxWidth: 280,
                  maxHeight: 120,
                  fallback: Text(
                    item.name,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: SoupType.style(
                      size: item.name.length > 28 ? 28 : 36,
                      weight: 800,
                      letterSpacing: -1.2,
                      height: 1.02,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                MetaLine(
                  bits: meta,
                  chips: chips,
                  size: 13,
                  spacing: 14,
                  color: SoupColors.muted,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.item,
    required this.audio,
    required this.subtitle,
    required this.quality,
    this.seasonId,
  });
  final CatalogItem item;
  final int? audio;
  final int? subtitle;

  /// Bitrate cap; null = Auto.
  final int? quality;

  /// The season picked below, for a series.
  final String? seasonId;

  @override
  Widget build(BuildContext context) {
    if (item.type == 'Series') {
      return CatalogBuilder<(CatalogItem?, List<CatalogItem>)>(
        load: (c) async =>
            (await c.seriesNextUp(item.id), await c.seasons(item.id)),
        keys: [item.id],
        builder: (context, data, _) {
          final seasons = data?.$2 ?? const <CatalogItem>[];
          return _buttons(
            context,
            data?.$1,
            // With several seasons, Watched covers the one on screen.
            season: seasons.length > 1 ? pickSeason(seasons, seasonId) : null,
          );
        },
      );
    }
    return _buttons(context, item.isPlayable ? item : null);
  }

  /// Phones (web below `sm`): Play full width, then the rest as equal
  /// tiles.
  Widget _buttons(
    BuildContext context,
    CatalogItem? target, {
    CatalogItem? season,
  }) {
    final scope = SoupScope.of(context);
    final watchTarget = season ?? item;
    final own = target?.id == item.id;
    final resumable = target != null && canResume(target);
    final tiles = <Widget>[
      if (resumable)
        _Tile(
          icon: Icons.replay_rounded,
          label: 'Play from start',
          onTap: () => openWatch(context, target, fromStart: true),
        ),
      if (item.type != 'BoxSet')
        WatchedToggle(
          target: watchTarget,
          builder: (context, played, toggle) => _Tile(
            icon: Icons.check_rounded,
            label: played ? 'Watched' : 'Mark as watched',
            filled: played,
            onTap: toggle,
          ),
        ),
      _Tile(
        icon: Icons.more_horiz_rounded,
        label: 'More',
        onTap: () => _more(context, scope, allEpisodes: season != null),
      ),
    ];
    return Column(
      children: [
        if (target != null) ...[
          PlayButton(
            compact: true,
            expand: true,
            height: 52,
            label: playLabel(item, target),
            detail: resumable ? timeLeftLabel(target) : null,
            progress: isInProgress(target)
                ? (target.playedPercentage ?? 0) / 100
                : 0,
            onActivate: () => openWatch(
              context,
              target,
              audioIndex: own ? audio : null,
              subtitleIndex: own ? subtitle : null,
              maxBitrate: own ? (quality ?? 0) : null,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: tiles[i]),
            ],
          ],
        ),
      ],
    );
  }

  /// [allEpisodes]: offer marking the whole series, when Watched covers
  /// only a season.
  void _more(
    BuildContext context,
    SoupScope scope, {
    bool allEpisodes = false,
  }) {
    final favorite = scope.catalog.isFavorite(item);
    final seriesId = item.seriesId;
    unawaited(
      showActionMenu(context, [
        MenuAction(
          label: favorite ? 'Remove from Favourites' : 'Add to Favourites',
          icon: favorite
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
          iconColor: favorite ? SoupColors.accent : SoupColors.ink,
          onSelected: () => scope.catalog.setFavorite(item.id, !favorite),
        ),
        if (allEpisodes)
          MenuAction(
            label: item.played
                ? 'Mark all episodes as unwatched'
                : 'Mark all episodes as watched',
            icon: Icons.done_all_rounded,
            iconColor: item.played ? SoupColors.accent : SoupColors.ink,
            onSelected: () => scope.catalog.setPlayed(item.id, !item.played),
          ),
        if (item.type == 'Episode' && seriesId != null)
          MenuAction(
            label: 'Go to series',
            icon: Icons.chevron_right_rounded,
            onSelected: () => openItemId(context, seriesId),
          ),
      ]),
    );
  }
}

/// Icon over a short label, for the row under Play.
class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: Focusable(
      radius: SoupRadii.button,
      scale: 1.0,
      onActivate: onTap,
      builder: (context, focused) => Container(
        height: 60,
        decoration: BoxDecoration(
          color: filled
              ? SoupColors.ink
              : (focused ? SoupColors.glassFocused : SoupColors.glass),
          borderRadius: BorderRadius.circular(SoupRadii.button),
          border: filled ? null : Border.all(color: SoupColors.faint),
        ),
        child: ExcludeSemantics(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 22,
                color: filled ? SoupColors.canvas : SoupColors.ink,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SoupType.style(
                  size: 12,
                  weight: 700,
                  color: filled ? SoupColors.canvas : SoupColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Overview clamped to four lines; tap to expand.
/// Season pills over a vertical episode list.
class _Episodes extends StatelessWidget {
  const _Episodes({
    required this.series,
    required this.seasonId,
    required this.onSeason,
  });
  final CatalogItem series;
  final String? seasonId;
  final ValueChanged<String> onSeason;

  @override
  Widget build(BuildContext context) {
    return CatalogBuilder<List<CatalogItem>>(
      load: (c) => c.seasons(series.id),
      keys: [series.id],
      builder: (context, seasons, _) {
        if (seasons == null || seasons.isEmpty) return const SizedBox.shrink();
        final selected = pickSeason(seasons, seasonId);
        return CatalogBuilder<List<CatalogItem>>(
          load: (c) => c.episodes(series.id, selected.id),
          keys: [series.id, selected.id],
          builder: (context, episodes, _) {
            final watched = episodes?.where((e) => e.played).length ?? 0;
            final next = episodes?.where((e) => !e.played).firstOrNull;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TouchSectionTitle(
                  'Episodes',
                  trailing: episodes == null
                      ? null
                      : Text(
                          '$watched of ${episodes.length} watched',
                          style: SoupType.style(
                            size: 13,
                            weight: 600,
                            color: SoupColors.muted,
                          ),
                        ),
                ),
                if (seasons.length > 1) ...[
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: TouchSpacing.gutter,
                    ),
                    child: PillTabs<String>(
                      options: [for (final s in seasons) s.id],
                      value: selected.id,
                      labelOf: (id) =>
                          seasons.firstWhere((s) => s.id == id).name,
                      checkedOf: (id) =>
                          seasons.firstWhere((s) => s.id == id).played,
                      onChanged: onSeason,
                      height: 38,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                if (episodes == null)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: SoupColors.accent,
                      ),
                    ),
                  )
                else
                  for (final e in episodes)
                    _EpisodeTile(episode: e, isNext: e.id == next?.id),
              ],
            );
          },
        );
      },
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({required this.episode, required this.isNext});
  final CatalogItem episode;
  final bool isNext;

  @override
  Widget build(BuildContext context) {
    final progress = isInProgress(episode)
        ? (episode.playedPercentage ?? 0) / 100
        : 0.0;
    final runtime = runtimeLabel(episode.runTimeTicks);
    return Focusable(
      radius: SoupRadii.card,
      scale: 1.0,
      onActivate: () => openItem(context, episode),
      builder: (context, focused) => Container(
        color: focused ? SoupColors.surface : Colors.transparent,
        padding: const EdgeInsets.symmetric(
          horizontal: TouchSpacing.gutter,
          vertical: 14,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 144,
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CatalogImage(
                            image: episode.landscape,
                            maxWidth: 400,
                            fallbackTitle: episode.name,
                            fallbackFontSize: 13,
                          ),
                          // The tile opens the episode; its play badge plays it.
                          Center(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => openWatch(context, episode),
                              child: const Padding(
                                padding: EdgeInsets.all(12),
                                child: Icon(
                                  Icons.play_circle_fill_rounded,
                                  size: 32,
                                  color: Color(0xCCFFFFFF),
                                ),
                              ),
                            ),
                          ),
                          if (episode.played)
                            const Positioned(
                              top: 4,
                              right: 4,
                              child: Icon(
                                Icons.check_circle_rounded,
                                size: 18,
                                color: SoupColors.ink,
                              ),
                            ),
                          if (progress > 0)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: LinearProgressIndicator(
                                value: progress.clamp(0, 1),
                                minHeight: 3,
                                color: SoupColors.accent,
                                backgroundColor: const Color(0x66000000),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isNext)
                        Text(
                          'UP NEXT',
                          style: SoupType.style(
                            size: 11,
                            weight: 800,
                            color: SoupColors.accent,
                            letterSpacing: 0.5,
                          ),
                        ),
                      Text(
                        '${episode.indexNumber != null ? '${episode.indexNumber}. ' : ''}${episode.name}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: SoupType.style(size: 15, weight: 700),
                      ),
                      if (runtime != null)
                        Text(
                          runtime,
                          style: SoupType.style(
                            size: 13,
                            weight: 600,
                            color: SoupColors.muted,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (episode.overview != null && episode.overview!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  episode.overview!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: SoupType.style(
                    size: 13,
                    color: SoupColors.muted,
                    height: 1.35,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Cast extends StatelessWidget {
  const _Cast({required this.people});
  final List<Person> people;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const TouchSectionTitle('Cast & Crew'),
      const SizedBox(height: 10),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: TouchSpacing.gutter),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final p in people.take(24))
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: PersonCard(person: p, showRole: true, size: 76),
              ),
          ],
        ),
      ),
    ],
  );
}

class _Information extends StatelessWidget {
  const _Information({required this.item});
  final CatalogItem item;

  @override
  Widget build(BuildContext context) {
    final rows = itemInformation(item);
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: TouchSpacing.gutter),
      child: Container(
        padding: const EdgeInsets.only(top: 20),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: SoupColors.elevated)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Information',
              style: SoupType.style(size: 20, weight: 800, letterSpacing: -0.4),
            ),
            const SizedBox(height: 12),
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 110,
                      child: Text(
                        r.$1,
                        style: SoupType.style(size: 14, weight: 700),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        r.$2,
                        style: SoupType.style(
                          size: 14,
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
      ),
    );
  }
}

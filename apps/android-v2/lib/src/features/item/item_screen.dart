import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../data/models.dart';
import '../../form_factor.dart';
import '../../navigation.dart';
import '../../ui/theme/soup_tokens.dart';
import '../../ui/widgets/action_menu.dart';
import '../../ui/widgets/catalog_builder.dart';
import '../../ui/widgets/catalog_image.dart';
import '../../ui/widgets/expandable_overview.dart';
import '../../ui/widgets/focusable.dart';
import '../../ui/widgets/glass_nav.dart';
import '../../ui/widgets/hero_carousel.dart';
import '../../ui/widgets/media_card.dart';
import '../../ui/widgets/media_row.dart';
import '../../ui/widgets/meta_line.dart';
import '../../ui/widgets/page_scaffold.dart';
import '../../ui/widgets/person_card.dart';
import '../../ui/widgets/pill_tabs.dart';
import '../../ui/widgets/play_button.dart';
import '../../ui/widgets/title_art.dart';
import '../../ui/widgets/error_state.dart';
import '../../utils/media.dart';
import 'episode_parts.dart';
import 'item_screen_touch.dart';

/// The big button's label: Resume, the series' next episode, or Play.
String playLabel(CatalogItem item, CatalogItem target) {
  if (canResume(target)) return 'Resume';
  if (item.type == 'Series' && target.indexNumber != null) {
    return 'Play S${target.parentIndexNumber ?? 1}:E${target.indexNumber}';
  }
  return 'Play';
}

/// Web `pages/item/[id].vue`: hero, play controls, seasons/episodes, cast,
/// information and related titles. An episode leads with its own still and
/// keeps the show to a small card.
class ItemScreen extends StatefulWidget {
  const ItemScreen({required this.itemId, super.key});
  final String itemId;

  @override
  State<ItemScreen> createState() => _ItemScreenState();
}

class _ItemScreenState extends State<ItemScreen> {
  int? _audio; // null = default
  int? _subtitle; // null = per settings, -1 = off
  String? _seasonId;
  int? _quality; // bitrate cap, null = Auto; only once picked here
  bool _qualityPicked = false;

  @override
  Widget build(BuildContext context) {
    if (context.isTouch) return TouchItemScreen(itemId: widget.itemId);
    return CatalogBuilder<CatalogItem>(
      load: (c) => c.item(widget.itemId),
      keys: [widget.itemId],
      builder: (context, item, error) {
        if (item == null) {
          return PageScaffold(
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
        return PageScaffold(
          section: NavSection.none,
          slivers: [
            SliverToBoxAdapter(
              child: item.type == 'Episode'
                  ? _EpisodeHero(item: item, state: this)
                  : _Hero(item: item, state: this),
            ),
            SliverToBoxAdapter(
              child: _Body(item: item, state: this),
            ),
          ],
        );
      },
    );
  }

  void setAudio(int? v) => setState(() => _audio = v);
  void setSubtitle(int? v) => setState(() => _subtitle = v);
  void setSeason(String? v) => setState(() => _seasonId = v);
  void setQuality(int? v) => setState(() {
    _quality = v;
    _qualityPicked = true;
  });
  int? get audio => _audio;

  /// The picked cap, else the one Settings prefers.
  int? get quality =>
      _qualityPicked ? _quality : SoupScope.of(context).prefs.maxBitrate;
  int? get subtitle => _subtitle;
  String? get seasonId => _seasonId;
}

class _Hero extends StatelessWidget {
  const _Hero({required this.item, required this.state});
  final CatalogItem item;
  final _ItemScreenState state;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final minHeight = (size.height * 0.88).clamp(0.0, 720.0);
    final isEpisode = item.type == 'Episode';
    final meta = <String>[
      ?yearLabel(item),
      ?runtimeLabel(item.runTimeTicks),
      ...item.genres.take(3),
      if (item.communityRating != null)
        '★ ${item.communityRating!.toStringAsFixed(1)}',
    ];
    final chips = <String>[?item.officialRating, ...qualityBadges(item)];
    final title = Text(
      item.name,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: SoupType.style(
        size: heroTitleSize(item.name, size.width).clamp(40, 80),
        weight: 800,
        letterSpacing: -2.5,
        height: 0.95,
      ),
    );

    return SizedBox(
      height: minHeight < 520 ? 520 : minHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CatalogImage(
            image: item.backdrop,
            maxWidth: 1600,
            alignment: Alignment.topCenter,
          ),
          const ArtScrims(),
          Positioned(
            left: SoupSpacing.gutter,
            right: SoupSpacing.gutter,
            bottom: 24,
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 820),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isEpisode) ...[
                          Text(
                            item.seriesName ?? '',
                            style: SoupType.style(size: 24, weight: 800),
                          ),
                          if (episodeCode(item) case final label?)
                            Text(
                              label,
                              style: SoupType.style(
                                size: 17,
                                weight: 700,
                                color: SoupColors.ink2,
                              ),
                            ),
                          const SizedBox(height: 8),
                          title,
                        ] else
                          // Episodes keep the text: the show's logo would read as
                          // the show rather than this episode.
                          TitleArt(
                            logo: item.logo,
                            maxWidth: 560,
                            maxHeight: 210,
                            fallback: title,
                          ),
                        const SizedBox(height: 14),
                        MetaLine(bits: meta, chips: chips),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Full width: the buttons outgrow the text column.
                  _Actions(item: item, state: state),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Still with prev/next under it on the left; title, actions, pickers,
/// overview (clamped) and credits on the right.
class _EpisodeHero extends StatelessWidget {
  const _EpisodeHero({required this.item, required this.state});
  final CatalogItem item;
  final _ItemScreenState state;

  @override
  Widget build(BuildContext context) {
    final label = episodeLabel(item);
    final chips = <String>[?item.officialRating, ...qualityBadges(item)];
    final overview = item.overview;
    final (titleSize, titleHeight) = episodeTitleSize(item.name);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SoupSpacing.gutter,
        112,
        SoupSpacing.gutter,
        0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 14,
            child: Column(
              children: [
                EpisodeStill(item: item),
                const SizedBox(height: 14),
                AdjacentEpisodes(item: item),
              ],
            ),
          ),
          const SizedBox(width: 48),
          Expanded(
            flex: 10,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (label != null) ...[
                  Text(
                    label.toUpperCase(),
                    style: SoupType.style(
                      size: 15,
                      weight: 800,
                      color: SoupColors.accent,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Text(
                  item.name,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: SoupType.style(
                    size: titleSize,
                    weight: 800,
                    letterSpacing: -1.5,
                    height: titleHeight,
                  ),
                ),
                const SizedBox(height: 14),
                MetaLine(bits: episodeMeta(item), chips: chips),
                const SizedBox(height: 24),
                _Actions(item: item, state: state),
                const SizedBox(height: 20),
                TrackPickers(
                  item: item,
                  audio: state.audio,
                  subtitle: state.subtitle,
                  quality: state.quality,
                  onAudio: state.setAudio,
                  onSubtitle: state.setSubtitle,
                  onQuality: state.setQuality,
                ),
                if (overview != null && overview.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  ExpandableOverview(
                    text: overview,
                    maxLines: 4,
                    style: SoupType.style(
                      size: 17,
                      color: SoupColors.ink2,
                      height: 1.45,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                EpisodeCredits(item: item),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Track pickers and overview, under the hero so a long overview never
/// pushes the title up (web item page).
class _Details extends StatelessWidget {
  const _Details({required this.item, required this.state});
  final CatalogItem item;
  final _ItemScreenState state;

  @override
  Widget build(BuildContext context) {
    final overview = item.overview;
    // Pickers only apply when Play starts this item (not a series' episode).
    final tracks = item.isPlayable && item.mediaStreams.isNotEmpty;
    if (!tracks && (overview == null || overview.isEmpty)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SoupSpacing.gutter,
        16,
        SoupSpacing.gutter,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (tracks)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: TrackPickers(
                item: item,
                audio: state.audio,
                subtitle: state.subtitle,
                quality: state.quality,
                onAudio: state.setAudio,
                onSubtitle: state.setSubtitle,
                onQuality: state.setQuality,
              ),
            ),
          if (overview != null && overview.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ExpandableOverview(
                text: overview,
                style: SoupType.style(
                  size: 17,
                  color: SoupColors.ink2,
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.item, required this.state});
  final CatalogItem item;
  final _ItemScreenState state;

  @override
  Widget build(BuildContext context) {
    if (item.type == 'Series') {
      // Wrapped in a record so "still loading" (null) differs from "no next
      // episode" ((null, …)): nothing should grab focus until we know which.
      return CatalogBuilder<(CatalogItem?, List<CatalogItem>)>(
        load: (c) async =>
            (await c.seriesNextUp(item.id), await c.seasons(item.id)),
        keys: [item.id],
        builder: (context, data, error) {
          final seasons = data?.$2 ?? const <CatalogItem>[];
          return _row(
            context,
            playTarget: data?.$1,
            loading: data == null && error == null,
            // With several seasons, Watched covers the one on screen.
            season: seasons.length > 1
                ? pickSeason(seasons, state.seasonId)
                : null,
          );
        },
      );
    }
    return _row(context, playTarget: item.isPlayable ? item : null);
  }

  Widget _row(
    BuildContext context, {
    CatalogItem? playTarget,
    bool loading = false,
    CatalogItem? season,
  }) {
    final scope = SoupScope.of(context);
    final watchTarget = season ?? item;
    final resumable = playTarget != null && canResume(playTarget);
    final watchable = item.type != 'BoxSet';
    final isEpisode = item.type == 'Episode';
    // With nothing to play, the first button takes focus once loading ends;
    // keyed on [loading] so its autofocus can still fire then.
    final fallbackFocus = !loading && playTarget == null;
    // Wraps rather than overflowing in an episode's narrower details column.
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 16,
      children: [
        if (playTarget != null) ...[
          PlayButton(
            autofocus: true,
            label: playLabel(item, playTarget),
            detail: resumable ? timeLeftLabel(playTarget) : null,
            progress: isInProgress(playTarget)
                ? (playTarget.playedPercentage ?? 0) / 100
                : 0,
            onActivate: () => openWatch(
              context,
              playTarget,
              audioIndex: playTarget.id == item.id ? state.audio : null,
              subtitleIndex: playTarget.id == item.id ? state.subtitle : null,
              maxBitrate: playTarget.id == item.id
                  ? (state.quality ?? 0)
                  : null,
            ),
          ),
          const SizedBox(width: 16),
        ],
        // Episodes use round icon buttons so the row fits beside the still.
        if (resumable) ...[
          if (isEpisode)
            _RoundAction(
              icon: Icons.replay_rounded,
              semanticsLabel: 'Play from start',
              onTap: () => openWatch(context, playTarget, fromStart: true),
            )
          else
            _PillAction(
              icon: Icons.replay_rounded,
              label: 'Play from start',
              onTap: () => openWatch(context, playTarget, fromStart: true),
            ),
          const SizedBox(width: 16),
        ],
        if (watchable) ...[
          WatchedToggle(
            key: ValueKey(('watched', loading)),
            target: watchTarget,
            builder: (context, played, toggle) => isEpisode
                ? _RoundAction(
                    icon: Icons.check_rounded,
                    semanticsLabel: played ? 'Watched' : 'Mark as watched',
                    filled: played,
                    autofocus: fallbackFocus,
                    onTap: toggle,
                  )
                : _PillAction(
                    icon: Icons.check_rounded,
                    label: played ? 'Watched' : 'Mark as watched',
                    filled: played,
                    autofocus: fallbackFocus,
                    onTap: toggle,
                  ),
          ),
          const SizedBox(width: 16),
        ],
        _RoundAction(
          key: ValueKey(('more', loading)),
          icon: Icons.more_horiz_rounded,
          semanticsLabel: 'More actions',
          autofocus: fallbackFocus && !watchable,
          onTap: () => _more(context, scope, allEpisodes: season != null),
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

/// A watched toggle that flips the moment it's pressed rather than after the
/// server write and refetch, and reverts if the write fails.
class WatchedToggle extends StatefulWidget {
  const WatchedToggle({required this.target, required this.builder, super.key});
  final CatalogItem target;
  final Widget Function(BuildContext context, bool played, VoidCallback toggle)
  builder;

  @override
  State<WatchedToggle> createState() => _WatchedToggleState();
}

class _WatchedToggleState extends State<WatchedToggle> {
  bool? _shown; // pressed state, until the refetched item agrees
  bool _writing = false;

  bool get _played => _shown ?? widget.target.played;

  @override
  void didUpdateWidget(WatchedToggle old) {
    super.didUpdateWidget(old);
    if (widget.target.id != old.target.id ||
        (!_writing && widget.target.played == _shown)) {
      _shown = null;
    }
  }

  void _toggle() {
    setState(() => _shown = !_played);
    if (!_writing) unawaited(_write());
  }

  /// One request at a time, until the server has the latest pressed state,
  /// so quick presses can't land out of order.
  Future<void> _write() async {
    final catalog = SoupScope.of(context).catalog;
    final id = widget.target.id;
    _writing = true;
    bool? sent;
    try {
      while (mounted && widget.target.id == id) {
        final want = _shown;
        if (want == null || want == sent) break;
        await catalog.setPlayed(id, want);
        sent = want;
      }
    } on Object {
      if (mounted) setState(() => _shown = null);
      return;
    } finally {
      _writing = false;
    }
    if (mounted && widget.target.played == _shown) {
      setState(() => _shown = null);
    }
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _played, _toggle);
}

class _PillAction extends StatelessWidget {
  const _PillAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
    this.autofocus = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Focusable(
    autofocus: autofocus,
    radius: 28,
    onActivate: onTap,
    builder: (context, focused) => Container(
      height: 56,
      padding: const EdgeInsets.only(left: 18, right: 22),
      decoration: BoxDecoration(
        color: filled
            ? SoupColors.ink
            : (focused ? SoupColors.glassFocused : SoupColors.glass),
        borderRadius: BorderRadius.circular(28),
        border: filled ? null : Border.all(color: SoupColors.faint),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 24,
            color: filled ? SoupColors.canvas : SoupColors.ink,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: SoupType.style(
              size: 17,
              weight: 800,
              color: filled ? SoupColors.canvas : SoupColors.ink,
            ),
          ),
        ],
      ),
    ),
  );
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.onTap,
    required this.semanticsLabel,
    this.filled = false,
    this.autofocus = false,
    super.key,
  });
  final IconData icon;
  final VoidCallback onTap;
  final String semanticsLabel;
  final bool filled;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semanticsLabel,
    child: Focusable(
      autofocus: autofocus,
      radius: 28,
      onActivate: onTap,
      builder: (context, focused) => Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: filled
              ? SoupColors.ink
              : (focused ? SoupColors.glassFocused : SoupColors.glass),
          shape: BoxShape.circle,
          border: filled ? null : Border.all(color: SoupColors.faint),
        ),
        child: Icon(
          icon,
          size: 26,
          color: filled ? SoupColors.canvas : SoupColors.ink,
        ),
      ),
    ),
  );
}

class _Body extends StatelessWidget {
  const _Body({required this.item, required this.state});
  final CatalogItem item;
  final _ItemScreenState state;

  Widget _gap(Widget c) => Padding(
    padding: const EdgeInsets.only(top: SoupSpacing.rowGap),
    child: c,
  );

  @override
  Widget build(BuildContext context) {
    if (item.type == 'Episode') {
      // The show stays a small card; no cast rail or Related for one episode.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _gap(
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: SoupSpacing.gutter,
              ),
              child: ShowCard(item: item),
            ),
          ),
          _gap(_Information(item: item)),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Details(item: item, state: state),
        if (item.type == 'Series') _gap(_Seasons(series: item, state: state)),
        if (item.type == 'BoxSet') _gap(_Collection(item: item)),
        CatalogBuilder<List<CatalogItem>>(
          load: (c) => c.extras(item),
          keys: [item.id],
          builder: (context, extras, _) => extras == null || extras.isEmpty
              ? const SizedBox.shrink()
              : _gap(
                  MediaRow(
                    title: 'Extras',
                    items: extras,
                    shape: CardShape.landscape,
                    cardBuilder: (context, e, _) => MediaCard(
                      item: e,
                      shape: CardShape.landscape,
                      width: 400,
                      kicker: extraLabel(e),
                      showPlay: true,
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
            builder: (context, similar, _) => similar == null || similar.isEmpty
                ? const SizedBox.shrink()
                : _gap(
                    MediaRow(
                      title: 'Related',
                      items: similar,
                      shape: CardShape.poster,
                    ),
                  ),
          ),
      ],
    );
  }
}

class _Seasons extends StatelessWidget {
  const _Seasons({required this.series, required this.state});
  final CatalogItem series;
  final _ItemScreenState state;

  @override
  Widget build(BuildContext context) {
    return CatalogBuilder<List<CatalogItem>>(
      load: (c) => c.seasons(series.id),
      keys: [series.id],
      builder: (context, seasons, _) {
        if (seasons == null || seasons.isEmpty) return const SizedBox.shrink();
        final selected = pickSeason(seasons, state.seasonId);
        return CatalogBuilder<List<CatalogItem>>(
          load: (c) => c.episodes(series.id, selected.id),
          keys: [series.id, selected.id],
          builder: (context, episodes, _) {
            final watched = episodes?.where((e) => e.played).length ?? 0;
            final next = episodes?.where((e) => !e.played).firstOrNull;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SoupSpacing.gutter,
                  ),
                  child: Row(
                    children: [
                      Flexible(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: PillTabs<String>(
                            options: [for (final s in seasons) s.id],
                            value: selected.id,
                            labelOf: (id) =>
                                seasons.firstWhere((s) => s.id == id).name,
                            checkedOf: (id) =>
                                seasons.firstWhere((s) => s.id == id).played,
                            onChanged: state.setSeason,
                            height: 44,
                          ),
                        ),
                      ),
                      if (episodes != null) ...[
                        const SizedBox(width: 20),
                        Text(
                          '$watched of ${episodes.length} watched',
                          style: SoupType.style(
                            size: 15,
                            weight: 600,
                            color: SoupColors.muted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                MediaRow(
                  title: selected.name,
                  items: episodes ?? const [],
                  loading: episodes == null,
                  shape: CardShape.landscape,
                  cardBuilder: (context, e, _) =>
                      _EpisodeCard(episode: e, isNext: e.id == next?.id),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _EpisodeCard extends StatelessWidget {
  const _EpisodeCard({required this.episode, required this.isNext});
  final CatalogItem episode;
  final bool isNext;

  @override
  Widget build(BuildContext context) {
    final runtime = runtimeLabel(episode.runTimeTicks);
    return SizedBox(
      width: 340,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MediaCard(
            item: episode,
            shape: CardShape.landscape,
            width: 340,
            titleOverride:
                '${episode.indexNumber != null ? '${episode.indexNumber}. ' : ''}${episode.name}',
            detail: runtime,
            kicker: isNext ? 'Up next' : null,
            onTap: () => openItem(context, episode),
          ),
          if (episode.overview != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                episode.overview!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: SoupType.style(
                  size: 14,
                  color: SoupColors.muted,
                  height: 1.35,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Collection extends StatelessWidget {
  const _Collection({required this.item});
  final CatalogItem item;

  @override
  Widget build(BuildContext context) => CatalogBuilder<List<CatalogItem>>(
    load: (c) => c.children(item.id),
    keys: [item.id],
    builder: (context, children, _) => MediaRow(
      title: 'In This Collection',
      items: children ?? const [],
      loading: children == null,
    ),
  );
}

class _Cast extends StatelessWidget {
  const _Cast({required this.people});
  final List<Person> people;

  @override
  Widget build(BuildContext context) {
    final shown = people.take(24).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: SoupSpacing.gutter),
          child: Text(
            'Cast & Crew',
            style: SoupType.style(size: 26, weight: 800, letterSpacing: -0.5),
          ),
        ),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          padding: const EdgeInsets.symmetric(
            horizontal: SoupSpacing.gutter,
            vertical: 12,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final p in shown)
                Padding(
                  padding: const EdgeInsets.only(right: 24),
                  child: PersonCard(person: p, showRole: true),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Information extends StatelessWidget {
  const _Information({required this.item});
  final CatalogItem item;

  @override
  Widget build(BuildContext context) {
    final rows = itemInformation(item);
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SoupSpacing.gutter),
      child: Container(
        padding: const EdgeInsets.only(top: 28),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: SoupColors.elevated)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Information',
              style: SoupType.style(size: 26, weight: 800, letterSpacing: -0.5),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 48,
              runSpacing: 22,
              children: [
                for (final r in rows)
                  SizedBox(
                    width: 260,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.$1,
                          style: SoupType.style(size: 14, weight: 700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          r.$2,
                          style: SoupType.style(
                            size: 14,
                            color: SoupColors.muted,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// "Information" label/value pairs shared by the TV and touch item screens.
List<(String, String)> itemInformation(CatalogItem item) {
  if (item.type == 'Episode') return episodeInformation(item);
  String? names(String type) {
    final list = [
      for (final p in item.people)
        if (p.type == type) p.name,
    ];
    return list.isEmpty ? null : list.take(4).join(', ');
  }

  final rows = <(String, String)>[
    if (item.genres.isNotEmpty) ('Genres', item.genres.join(', ')),
    if (names('Director') != null) ('Directors', names('Director')!),
    if (names('Writer') != null) ('Writers', names('Writer')!),
    if (item.studios.isNotEmpty) ('Studios', item.studios.take(4).join(', ')),
    if (item.premiereDate != null &&
        DateTime.tryParse(item.premiereDate!) != null)
      ('Released', _date(DateTime.parse(item.premiereDate!))),
    if (item.status != null) ('Status', item.status!),
    if (item.officialRating != null) ('Rated', item.officialRating!),
    if (item.criticRating != null)
      ('Critic score', '${item.criticRating!.round()}%'),
    if (item.sourceBitrate case final bitrate?)
      ('Bitrate', bitrateLabel(bitrate)),
    if (item.tags.isNotEmpty) ('Tags', item.tags.take(6).join(', ')),
  ];
  return rows;
}

String extraLabel(CatalogItem e) => switch (e.extraType) {
  'Trailer' => 'Trailer',
  'BehindTheScenes' => 'Behind the Scenes',
  'DeletedScene' => 'Deleted Scene',
  'Interview' => 'Interview',
  'Featurette' => 'Featurette',
  'Clip' => 'Clip',
  'Scene' => 'Scene',
  'Short' => 'Short',
  _ => 'Extra',
};

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
String _date(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

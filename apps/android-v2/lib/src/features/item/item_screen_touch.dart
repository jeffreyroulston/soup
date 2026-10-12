import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../data/models.dart';
import '../../navigation.dart';
import '../../ui/theme/soup_tokens.dart';
import '../../ui/touch/touch_scaffold.dart';
import '../../ui/touch/touch_widgets.dart';
import '../../ui/widgets/catalog_builder.dart';
import '../../ui/widgets/catalog_image.dart';
import '../../ui/widgets/focusable.dart';
import '../../ui/widgets/glass_nav.dart' show NavSection;
import '../../ui/widgets/hero_carousel.dart' show ArtScrims;
import '../../ui/widgets/media_card.dart';
import '../../ui/widgets/person_card.dart';
import '../../ui/widgets/pill_tabs.dart';
import '../../ui/widgets/select_menu.dart';
import '../../ui/widgets/expandable_overview.dart';
import '../../utils/media.dart';
import 'item_screen.dart';

/// Touch item page: artwork header, then one column of actions, overview,
/// episodes, extras, cast, information and related titles.
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
                      ? Padding(
                          padding: const EdgeInsets.all(TouchSpacing.gutter),
                          child: Text(
                            'Could not load this title. $error',
                            textAlign: TextAlign.center,
                            style: SoupType.style(
                              size: 16,
                              color: SoupColors.accent,
                            ),
                          ),
                        )
                      : const CircularProgressIndicator(
                          color: SoupColors.accent,
                        ),
                ),
              ),
            ],
          );
        }
        return TouchScaffold(
          section: NavSection.none,
          title: item.name,
          overlayTopBar: true,
          slivers: [
            SliverToBoxAdapter(child: _Header(item: item)),
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
    final audio = item.streamsOf(StreamKind.audio);
    final subs = item.streamsOf(StreamKind.subtitle);
    final progress = isInProgress(item)
        ? (item.playedPercentage ?? 0) / 100
        : 0.0;
    final left = timeLeftLabel(item);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: TouchSpacing.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          _Actions(item: item, audio: _audio, subtitle: _subtitle),
          if (progress > 0) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress.clamp(0, 1),
                minHeight: 4,
                color: SoupColors.accent,
                backgroundColor: const Color(0x33FFFFFF),
              ),
            ),
            if (left != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  left,
                  style: SoupType.style(
                    size: 13,
                    weight: 600,
                    color: SoupColors.muted,
                  ),
                ),
              ),
          ],
          if (audio.length > 1 || subs.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (audio.length > 1)
                  SelectMenu<int?>(
                    prefix: 'Audio',
                    icon: Icons.volume_up_rounded,
                    value: _audio,
                    options: [
                      const SelectOption(null, 'Default'),
                      for (final a in audio) SelectOption(a.index, a.label),
                    ],
                    onChanged: (v) => setState(() => _audio = v),
                  ),
                if (subs.isNotEmpty)
                  SelectMenu<int?>(
                    prefix: 'Subtitles',
                    icon: Icons.subtitles_outlined,
                    value: _subtitle,
                    options: [
                      const SelectOption(null, 'Default'),
                      const SelectOption(-1, 'Off'),
                      for (final s in subs) SelectOption(s.index, s.label),
                    ],
                    onChanged: (v) => setState(() => _subtitle = v),
                  ),
              ],
            ),
          ],
          if (item.overview != null && item.overview!.isNotEmpty) ...[
            const SizedBox(height: 18),
            ExpandableOverview(
              text: item.overview!,
              style: SoupType.style(
                size: 15,
                color: SoupColors.ink2,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _body(CatalogItem item) => Column(
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
          builder: (context, similar, _) => similar == null || similar.isEmpty
              ? const SizedBox.shrink()
              : _gap(TouchRow(title: 'Related', items: similar)),
        ),
    ],
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.item});
  final CatalogItem item;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isEpisode = item.type == 'Episode';
    final episodeLine = isEpisode
        ? [?item.seriesName, ?episodeCode(item)].join(' · ')
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
                Text(
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
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final c in chips) TouchChip(c),
                    Text(
                      meta.join(' · '),
                      style: SoupType.style(
                        size: 13,
                        weight: 600,
                        color: SoupColors.muted,
                      ),
                    ),
                  ],
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
  });
  final CatalogItem item;
  final int? audio;
  final int? subtitle;

  @override
  Widget build(BuildContext context) {
    if (item.type == 'Series') {
      return CatalogBuilder<(CatalogItem?,)>(
        load: (c) async => (await c.seriesNextUp(item.id),),
        keys: [item.id],
        builder: (context, next, _) => _buttons(context, next?.$1),
      );
    }
    return _buttons(context, item.isPlayable ? item : null);
  }

  Widget _buttons(BuildContext context, CatalogItem? target) {
    final scope = SoupScope.of(context);
    var label = 'Play';
    if (target != null) {
      if (canResume(target)) {
        label = 'Resume';
      } else if (item.type == 'Series' && target.indexNumber != null) {
        label = 'Play S${target.parentIndexNumber ?? 1}:E${target.indexNumber}';
      }
    }
    final own = target?.id == item.id;
    final favorite = ValueListenableBuilder(
      valueListenable: scope.catalog.favoriteOverrides,
      builder: (context, _, _) {
        final favorite = scope.catalog.isFavorite(item);
        return TouchIconButton(
          tooltip: favorite ? 'Remove from favourites' : 'Add to favourites',
          icon: favorite
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
          color: favorite ? SoupColors.accent : SoupColors.ink,
          size: 52,
          onPressed: () => scope.catalog.setFavorite(item.id, !favorite),
        );
      },
    );
    return Column(
      children: [
        Row(
          children: [
            if (target != null)
              Expanded(
                child: TouchButton(
                  label: label,
                  icon: Icons.play_arrow_rounded,
                  expand: true,
                  height: 52,
                  onPressed: () => openWatch(
                    context,
                    target,
                    audioIndex: own ? audio : null,
                    subtitleIndex: own ? subtitle : null,
                  ),
                ),
              ),
            if (item.type != 'Series' && item.type != 'BoxSet') ...[
              const SizedBox(width: 10),
              TouchIconButton(
                tooltip: item.played ? 'Mark unwatched' : 'Mark watched',
                icon: Icons.check_rounded,
                filled: item.played,
                size: 52,
                onPressed: () => scope.catalog.setPlayed(item.id, !item.played),
              ),
            ],
            const SizedBox(width: 10),
            favorite,
          ],
        ),
        if (target != null && canResume(target)) ...[
          const SizedBox(height: 10),
          TouchButton(
            label: 'Play from start',
            icon: Icons.replay_rounded,
            primary: false,
            expand: true,
            onPressed: () => openWatch(context, target, fromStart: true),
          ),
        ],
      ],
    );
  }
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
        final selected = seasons.firstWhere(
          (s) => s.id == seasonId,
          orElse: () => seasons.firstWhere(
            (s) => (s.indexNumber ?? 0) > 0,
            orElse: () => seasons.first,
          ),
        );
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
      onActivate: () => openWatch(context, episode),
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
                          const Center(
                            child: Icon(
                              Icons.play_circle_fill_rounded,
                              size: 32,
                              color: Color(0xCCFFFFFF),
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

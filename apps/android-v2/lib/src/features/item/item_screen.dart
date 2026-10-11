import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../data/models.dart';
import '../../navigation.dart';
import '../../ui/theme/soup_tokens.dart';
import '../../ui/widgets/catalog_builder.dart';
import '../../ui/widgets/catalog_image.dart';
import '../../ui/widgets/focusable.dart';
import '../../ui/widgets/glass_nav.dart';
import '../../ui/widgets/hero_carousel.dart';
import '../../ui/widgets/media_card.dart';
import '../../ui/widgets/media_row.dart';
import '../../ui/widgets/page_scaffold.dart';
import '../../ui/widgets/person_card.dart';
import '../../ui/widgets/pill_tabs.dart';
import '../../ui/widgets/select_menu.dart';
import '../../utils/media.dart';

/// Web `pages/item/[id].vue`: hero, play controls, seasons/episodes, cast,
/// information and related titles.
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

  @override
  Widget build(BuildContext context) {
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
                      ? Text(
                          'Could not load this title. $error',
                          style: SoupType.style(
                            size: 18,
                            color: SoupColors.accent,
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
        return PageScaffold(
          section: NavSection.none,
          slivers: [
            SliverToBoxAdapter(
              child: _Hero(item: item, state: this),
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
  int? get audio => _audio;
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
    final isSeries = item.type == 'Series';
    final isEpisode = item.type == 'Episode';
    final isBoxSet = item.type == 'BoxSet';
    final kicker = isEpisode
        ? null
        : isSeries
        ? [
            'Series',
            if ((item.childCount ?? 0) > 0)
              '${item.childCount} Season${item.childCount == 1 ? '' : 's'}',
            if ((item.recursiveItemCount ?? 0) > 0)
              '${item.recursiveItemCount} Episodes',
          ].join(' · ')
        : isBoxSet
        ? 'Collection · ${item.childCount ?? ''} titles'
        : item.type == 'Movie'
        ? 'Movie'
        : item.type;
    final meta = <String>[
      ?yearLabel(item),
      ?runtimeLabel(item.runTimeTicks),
      ...item.genres.take(3),
    ];
    final chips = <String>[?item.officialRating, ...qualityBadges(item)];
    final audio = item.streamsOf(StreamKind.audio);
    final subs = item.streamsOf(StreamKind.subtitle);
    final left = timeLeftLabel(item);
    final progress = isInProgress(item)
        ? (item.playedPercentage ?? 0) / 100
        : 0.0;

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
            bottom: 48,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isEpisode) ...[
                        Text(
                          item.seriesName ?? '',
                          style: SoupType.style(size: 24, weight: 800),
                        ),
                        if (episodeCode(item) != null)
                          Text(
                            episodeCode(item)!,
                            style: SoupType.style(
                              size: 17,
                              weight: 700,
                              color: SoupColors.ink2,
                            ),
                          ),
                      ] else if (kicker != null)
                        Text(
                          kicker,
                          style: SoupType.style(
                            size: 15,
                            weight: 700,
                            color: SoupColors.ink2,
                          ),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        item.name,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: SoupType.style(
                          size: heroTitleSize(
                            item.name,
                            size.width,
                          ).clamp(40, 80),
                          weight: 800,
                          letterSpacing: -2.5,
                          height: 0.95,
                        ),
                      ),
                      const SizedBox(height: 22),
                      _Actions(item: item, state: state),
                      if (audio.length > 1 || subs.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            if (audio.length > 1)
                              SelectMenu<int?>(
                                prefix: 'Audio',
                                icon: Icons.volume_up_rounded,
                                value: state.audio,
                                options: [
                                  const SelectOption(null, 'Default'),
                                  for (final a in audio)
                                    SelectOption(a.index, a.label),
                                ],
                                onChanged: state.setAudio,
                              ),
                            if (subs.isNotEmpty)
                              SelectMenu<int?>(
                                prefix: 'Subtitles',
                                icon: Icons.subtitles_outlined,
                                value: state.subtitle,
                                options: [
                                  const SelectOption(null, 'Default'),
                                  const SelectOption(-1, 'Off'),
                                  for (final s in subs)
                                    SelectOption(s.index, s.label),
                                ],
                                onChanged: state.setSubtitle,
                              ),
                          ],
                        ),
                      ],
                      if (progress > 0) ...[
                        const SizedBox(height: 18),
                        SizedBox(
                          width: 320,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
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
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 48),
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (item.overview != null && item.overview!.isNotEmpty)
                        Text(
                          item.overview!,
                          maxLines: 6,
                          overflow: TextOverflow.ellipsis,
                          style: SoupType.style(
                            size: 17,
                            color: SoupColors.ink2,
                            height: 1.45,
                          ),
                        ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          for (final c in chips)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0x33FFFFFF),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                c,
                                style: SoupType.style(size: 12, weight: 800),
                              ),
                            ),
                          Text(
                            meta.join(' · '),
                            style: SoupType.style(
                              size: 15,
                              weight: 600,
                              color: SoupColors.muted,
                            ),
                          ),
                          if (item.communityRating != null)
                            Text(
                              '★ ${item.communityRating!.toStringAsFixed(1)}',
                              style: SoupType.style(
                                size: 15,
                                weight: 700,
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
    final scope = SoupScope.of(context);
    if (item.type == 'Series') {
      // Wrapped in a record so "still loading" (null) differs from "no next
      // episode" ((null,)): nothing should grab focus until we know which.
      return CatalogBuilder<(CatalogItem?,)>(
        load: (c) async => (await c.seriesNextUp(item.id),),
        keys: [item.id],
        builder: (context, next, error) => _row(
          context,
          scope,
          playTarget: next?.$1,
          loading: next == null && error == null,
        ),
      );
    }
    return _row(context, scope, playTarget: item.isPlayable ? item : null);
  }

  Widget _row(
    BuildContext context,
    SoupScope scope, {
    CatalogItem? playTarget,
    bool loading = false,
  }) {
    String label = 'Play';
    if (playTarget != null) {
      if (canResume(playTarget)) {
        label = 'Resume';
      } else if (item.type == 'Series' && playTarget.indexNumber != null) {
        label =
            'Play S${playTarget.parentIndexNumber ?? 1}:E${playTarget.indexNumber}';
      }
    }
    return Row(
      children: [
        if (playTarget != null)
          Focusable(
            autofocus: true,
            radius: SoupRadii.button,
            onActivate: () => openWatch(
              context,
              playTarget,
              audioIndex: playTarget.id == item.id ? state.audio : null,
              subtitleIndex: playTarget.id == item.id ? state.subtitle : null,
            ),
            builder: (context, _) => Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 30),
              decoration: BoxDecoration(
                color: SoupColors.ink,
                borderRadius: BorderRadius.circular(SoupRadii.button),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.play_arrow_rounded,
                    color: SoupColors.canvas,
                    size: 26,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: SoupType.style(
                      size: 18,
                      weight: 800,
                      color: SoupColors.canvas,
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(width: 12),
        _RoundAction(
          // Re-created once loading ends so its autofocus can still fire.
          key: ValueKey(loading),
          icon: item.isFavorite
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
          color: item.isFavorite ? SoupColors.accent : SoupColors.ink,
          autofocus: !loading && playTarget == null,
          onTap: () => scope.catalog.setFavorite(item.id, !item.isFavorite),
        ),
        const SizedBox(width: 12),
        if (item.type != 'Series' && item.type != 'BoxSet')
          _RoundAction(
            icon: Icons.check_rounded,
            filled: item.played,
            onTap: () => scope.catalog.setPlayed(item.id, !item.played),
          ),
        if (playTarget != null && canResume(playTarget)) ...[
          const SizedBox(width: 12),
          Focusable(
            radius: SoupRadii.button,
            onActivate: () => openWatch(context, playTarget, fromStart: true),
            builder: (context, focused) => Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 22),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: focused
                    ? const Color(0xBF48484E)
                    : const Color(0x99282828),
                borderRadius: BorderRadius.circular(SoupRadii.button),
                border: Border.all(color: const Color(0x1AFFFFFF)),
              ),
              child: Text(
                'Play from start',
                style: SoupType.style(size: 16, weight: 700),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.onTap,
    this.filled = false,
    this.color = SoupColors.ink,
    this.autofocus = false,
    super.key,
  });
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;
  final Color color;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Focusable(
    autofocus: autofocus,
    radius: 28,
    onActivate: onTap,
    builder: (context, focused) => Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: filled
            ? SoupColors.ink
            : (focused ? const Color(0xBF48484E) : const Color(0x99282828)),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0x1AFFFFFF)),
      ),
      child: Icon(icon, size: 26, color: filled ? SoupColors.canvas : color),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                      kicker: _extraLabel(e),
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

  static String _extraLabel(CatalogItem e) => switch (e.extraType) {
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
        final selected = seasons.firstWhere(
          (s) => s.id == state.seasonId,
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
            showPlay: true,
            titleOverride:
                '${episode.indexNumber != null ? '${episode.indexNumber}. ' : ''}${episode.name}',
            detail: runtime,
            kicker: isNext ? 'Up next' : null,
            onTap: () => openWatch(context, episode),
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
      if (item.tags.isNotEmpty) ('Tags', item.tags.take(6).join(', ')),
    ];
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

  static const _months = [
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
  static String _date(DateTime d) =>
      '${_months[d.month - 1]} ${d.day}, ${d.year}';
}

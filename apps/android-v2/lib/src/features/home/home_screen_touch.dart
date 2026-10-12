import 'package:flutter/material.dart';

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
import '../../ui/widgets/pill_tabs.dart';
import '../../utils/media.dart';
import 'home_screen.dart';

/// Touch Home: the same rows as the TV Home, as swipeable rails.
class TouchHomeScreen extends StatelessWidget {
  const TouchHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return CatalogBuilder<HomeData>(
      load: (c) => c.home(),
      builder: (context, home, error) => TouchScaffold(
        section: NavSection.home,
        overlayTopBar: true,
        slivers: [
          SliverToBoxAdapter(
            child: TouchHero(
              slides: home == null ? const [] : HomeScreen.heroSlides(home),
              loading: home == null && error == null,
            ),
          ),
          if (error != null && home == null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(TouchSpacing.gutter),
                child: Text(
                  'Could not load your library. $error',
                  style: SoupType.style(size: 16, color: SoupColors.accent),
                ),
              ),
            ),
          if (home != null) SliverToBoxAdapter(child: _Rows(home: home)),
        ],
      ),
    );
  }
}

class _Rows extends StatelessWidget {
  const _Rows({required this.home});
  final HomeData home;

  Widget _gap(Widget child) => Padding(
    padding: const EdgeInsets.only(top: TouchSpacing.rowGap),
    child: child,
  );

  static void _openShelfItem(BuildContext context, CatalogItem item) =>
      item.type == 'Episode' && item.seriesId != null
      ? openItemId(context, item.seriesId!)
      : openItem(context, item);

  Widget _shelf(Shelf shelf) => TouchRow(
    title: shelf.title,
    items: shelf.items,
    cardBuilder: (context, item, _) => MediaCard(
      item: item,
      width: TouchSpacing.posterWidth,
      onTap: () => _openShelfItem(context, item),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final keepWatching = [...home.resume, ...home.nextUp];
    final resumeIds = {for (final i in home.resume) i.id};
    return CatalogBuilder<HomeExtras>(
      load: (c) => c.homeExtras(),
      builder: (context, extras, _) => CatalogBuilder<List<Shelf>>(
        load: (c) => c.becauseYouWatched(),
        builder: (context, byw, _) => CatalogBuilder<List<Shelf>>(
          load: (c) => c.genreShelves(),
          builder: (context, genres, _) => CatalogBuilder<HomeCollection>(
            load: (c) => c.homeCollection(),
            builder: (context, collection, _) {
              final bywShelves = byw ?? const <Shelf>[];
              final genreShelves = genres ?? const <Shelf>[];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (keepWatching.isNotEmpty)
                    _gap(
                      TouchRow(
                        title: 'Keep Watching',
                        items: keepWatching,
                        shape: CardShape.landscape,
                        cardBuilder: (context, item, _) => MediaCard(
                          item: item,
                          shape: CardShape.landscape,
                          width: TouchSpacing.landscapeWidth,
                          kicker: resumeIds.contains(item.id)
                              ? 'Continue'
                              : 'Next',
                          onTap: () => item.isPlayable
                              ? openWatch(context, item)
                              : openItem(context, item),
                        ),
                      ),
                    ),
                  if (home.recentlyAdded.isNotEmpty)
                    _gap(_RecentlyAdded(shelves: home.recentlyAdded)),
                  if (extras != null && extras.topRated.isNotEmpty)
                    _gap(
                      TouchRow(
                        title: 'Top Rated',
                        items: extras.topRated,
                        shape: CardShape.landscape,
                        cardBuilder: (context, item, i) => MediaCard(
                          item: item,
                          shape: CardShape.landscape,
                          width: TouchSpacing.landscapeWidth,
                          kicker: '#${i + 1}',
                          detail: [
                            if (item.communityRating != null)
                              '★ ${item.communityRating!.toStringAsFixed(1)}',
                            ?item.genres.firstOrNull,
                            ?yearLabel(item),
                          ].join(' · '),
                        ),
                      ),
                    ),
                  if (bywShelves.isNotEmpty) _gap(_shelf(bywShelves.first)),
                  if (collection != null) ..._spotlight(context, collection),
                  for (final s in genreShelves.take(2)) _gap(_shelf(s)),
                  if (extras != null && extras.unwatchedTopRated.isNotEmpty)
                    _gap(
                      _shelf(
                        Shelf(
                          title: 'Highly Rated, Not Yet Watched',
                          items: extras.unwatchedTopRated,
                        ),
                      ),
                    ),
                  for (final s in bywShelves.skip(1)) _gap(_shelf(s)),
                  for (final s in genreShelves.skip(2)) _gap(_shelf(s)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _spotlight(BuildContext context, HomeCollection collection) {
    if (collection.curated.isNotEmpty) {
      final pick = dailyShuffle(collection.curated, 'spotlight').first;
      return [
        _gap(
          _Spotlight(
            title: pick.title,
            description: pick.description,
            countLabel: pick.countLabel,
            items: pick.items,
            onOpen: () => openCollection(context, pick.id),
          ),
        ),
      ];
    }
    final spot = collection.spotlight;
    if (spot == null || spot.items.isEmpty) return const [];
    return [
      _gap(
        _Spotlight(
          title: spot.collection.name,
          description: spot.collection.overview,
          countLabel: '${spot.items.length} titles',
          items: spot.items,
          onOpen: () => openItem(context, spot.collection),
        ),
      ),
    ];
  }
}

class _RecentlyAdded extends StatefulWidget {
  const _RecentlyAdded({required this.shelves});
  final List<Shelf> shelves;

  @override
  State<_RecentlyAdded> createState() => _RecentlyAddedState();
}

class _RecentlyAddedState extends State<_RecentlyAdded> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final i = _index.clamp(0, widget.shelves.length - 1);
    final shelf = widget.shelves[i];
    return TouchRow(
      key: ValueKey(shelf.libraryId),
      title: 'Recently Added',
      items: shelf.items,
      header: widget.shelves.length > 1
          ? PillTabs<int>(
              options: [for (var k = 0; k < widget.shelves.length; k++) k],
              value: i,
              labelOf: (k) => widget.shelves[k].title,
              onChanged: (k) => setState(() => _index = k),
              height: 36,
            )
          : null,
      cardBuilder: (context, item, _) => MediaCard(
        item: item,
        width: TouchSpacing.posterWidth,
        onTap: () => _Rows._openShelfItem(context, item),
      ),
    );
  }
}

/// Collection card: backdrop, title and a short poster fan.
class _Spotlight extends StatelessWidget {
  const _Spotlight({
    required this.title,
    required this.description,
    required this.countLabel,
    required this.items,
    required this.onOpen,
  });

  final String title;
  final String? description;
  final String countLabel;
  final List<CatalogItem> items;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final art = items.firstWhere(
      (i) => i.hasBackdrop,
      orElse: () => items.first,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: TouchSpacing.gutter),
      child: Focusable(
        radius: SoupRadii.panel,
        onActivate: onOpen,
        builder: (context, _) => ClipRRect(
          borderRadius: BorderRadius.circular(SoupRadii.panel),
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CatalogImage(
                  image: art.backdrop,
                  maxWidth: 900,
                  alignment: Alignment.topCenter,
                ),
                const ArtScrims(),
                Positioned(
                  left: 18,
                  right: 18,
                  bottom: 18,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Collection · $countLabel',
                        style: SoupType.style(
                          size: 12,
                          weight: 700,
                          color: SoupColors.ink2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: SoupType.style(
                          size: 28,
                          weight: 800,
                          letterSpacing: -1,
                          height: 1,
                        ),
                      ),
                      if (description != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          description!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: SoupType.style(
                            size: 13,
                            color: SoupColors.ink2,
                            height: 1.35,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: SoupColors.ink,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Watch the collection',
                          style: SoupType.style(
                            size: 14,
                            weight: 800,
                            color: SoupColors.canvas,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../navigation.dart';
import '../../ui/theme/soup_tokens.dart';
import '../../ui/widgets/catalog_builder.dart';
import '../../ui/widgets/collection_spotlight.dart';
import '../../ui/widgets/glass_nav.dart';
import '../../ui/widgets/hero_carousel.dart';
import '../../ui/widgets/media_card.dart';
import '../../ui/widgets/media_row.dart';
import '../../ui/widgets/page_scaffold.dart';
import '../../ui/widgets/rank_list.dart';
import '../../ui/widgets/shelf_rows.dart';
import '../../utils/media.dart';

/// Web `pages/index.vue`: hero, Keep Watching, Recently Added, Top Rated,
/// because-you-watched, spotlight, genres, highly rated.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static List<HeroSlide> heroSlides(HomeData home) {
    final seen = <String>{};
    final slides = <HeroSlide>[];
    void add(CatalogItem item, String kicker) {
      if (slides.length >= 6 || !item.hasBackdrop) return;
      if (!seen.add(item.seriesId ?? item.id)) return;
      slides.add(HeroSlide(item, kicker));
    }

    for (final i in home.resume) {
      add(i, 'Continue Watching');
    }
    for (final shelf in home.recentlyAdded) {
      for (final i in shelf.items) {
        add(i, 'Recently Added');
      }
    }
    return slides;
  }

  @override
  Widget build(BuildContext context) {
    return CatalogBuilder<HomeData>(
      load: (c) => c.home(),
      builder: (context, home, error) {
        return PageScaffold(
          section: NavSection.home,
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HeroCarousel(
                    slides: home == null ? const [] : heroSlides(home),
                    loading: home == null && error == null,
                  ),
                  if (error != null && home == null)
                    Padding(
                      padding: const EdgeInsets.all(SoupSpacing.gutter),
                      child: Text(
                        'Could not load your library. $error',
                        style: SoupType.style(
                          size: 18,
                          color: SoupColors.accent,
                        ),
                      ),
                    ),
                  if (home != null) _Rows(home: home),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Rows extends StatelessWidget {
  const _Rows({required this.home});
  final HomeData home;

  Widget _gap(Widget child) => Padding(
    padding: const EdgeInsets.only(top: SoupSpacing.rowGap),
    child: child,
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
                      MediaRow(
                        title: 'Keep Watching',
                        items: keepWatching,
                        shape: CardShape.landscape,
                        cardBuilder: (context, item, _) => MediaCard(
                          item: item,
                          shape: CardShape.landscape,
                          width: 400,
                          kicker: resumeIds.contains(item.id)
                              ? 'Continue'
                              : 'Next',
                          showPlay: true,
                          onTap: () => item.isPlayable
                              ? openWatch(context, item)
                              : openItem(context, item),
                        ),
                      ),
                    ),
                  if (home.recentlyAdded.isNotEmpty)
                    _gap(RecentlyAddedRow(shelves: home.recentlyAdded)),
                  if (extras != null && extras.topRated.isNotEmpty)
                    _gap(RankList(title: 'Top Rated', items: extras.topRated)),
                  if (bywShelves.isNotEmpty)
                    _gap(ShelfRow(shelf: bywShelves.first)),
                  if (collection != null) ..._spotlight(context, collection),
                  for (final s in genreShelves.take(2))
                    _gap(ShelfRow(shelf: s)),
                  if (extras != null && extras.unwatchedTopRated.isNotEmpty)
                    _gap(
                      ShelfRow(
                        shelf: Shelf(
                          title: 'Highly Rated, Not Yet Watched',
                          items: extras.unwatchedTopRated,
                        ),
                      ),
                    ),
                  for (final s in bywShelves.skip(1)) _gap(ShelfRow(shelf: s)),
                  for (final s in genreShelves.skip(2))
                    _gap(ShelfRow(shelf: s)),
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
      return [_gap(CollectionSpotlight.curated(pick, context))];
    }
    final spot = collection.spotlight;
    if (spot == null) return const [];
    return [
      _gap(
        CollectionSpotlight(
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

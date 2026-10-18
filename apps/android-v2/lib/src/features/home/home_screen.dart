import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../form_factor.dart';
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
import '../../ui/widgets/error_state.dart';
import '../../utils/media.dart';
import 'home_screen_touch.dart';

/// Web `pages/index.vue`: hero, Keep Watching, Recently Added, Top Rated,
/// because-you-watched, spotlight, genres, highly rated.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  /// Only things that reached the server this recently count as "new" in the
  /// hero (new seasons, new episodes, recently added).
  static const heroRecentWindow = Duration(days: 14);

  /// Hero order: new seasons of shows you watch, then new episodes of them,
  /// then Continue Watching, then recently added, then random picks.
  static List<HeroSlide> heroSlides(HomeData home, {DateTime? now}) {
    final cutoff = (now ?? DateTime.now()).subtract(heroRecentWindow);
    bool isRecent(CatalogItem i) =>
        i.dateAdded != null && i.dateAdded!.isAfter(cutoff);
    // Next Up only lists shows you've already started.
    final freshNextUp = home.nextUp.where(isRecent).toList();
    bool isSeasonPremiere(CatalogItem i) =>
        i.indexNumber == 1 && (i.parentIndexNumber ?? 0) > 1;

    final seen = <String>{};
    final slides = <HeroSlide>[];
    void add(CatalogItem item) {
      if (slides.length >= 6 || !item.hasBackdrop) return;
      if (!seen.add(item.seriesId ?? item.id)) return;
      slides.add(HeroSlide(item));
    }

    freshNextUp.where(isSeasonPremiere).forEach(add);
    freshNextUp.forEach(add);
    home.resume.forEach(add);
    // Newest first across every library, not library by library.
    final added = [
      for (final shelf in home.recentlyAdded) ...shelf.items.where(isRecent),
    ]..sort((a, b) => b.dateAdded!.compareTo(a.dateAdded!));
    added.forEach(add);
    home.random.forEach(add);
    return slides;
  }

  @override
  Widget build(BuildContext context) {
    if (context.isTouch) return const TouchHomeScreen();
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
                  if (error != null && home == null) ErrorState(error: error),
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

  /// [id] keeps each row's element (and focus) its own when rows that
  /// load later are inserted above it.
  Widget _gap(String id, Widget child) => Padding(
    key: ValueKey(id),
    padding: const EdgeInsets.only(top: SoupSpacing.rowGap),
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final keepWatching = home.keepWatching;
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
                      'keepWatching',
                      MediaRow(
                        title: 'Keep Watching',
                        items: keepWatching,
                        shape: CardShape.landscape,
                        cardBuilder: (context, item, _) => MediaCard(
                          item: item,
                          favoriteButton: false,
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
                    _gap(
                      'recent',
                      RecentlyAddedRow(shelves: home.recentlyAdded),
                    ),
                  if (extras != null && extras.topRated.isNotEmpty)
                    _gap(
                      'topRated',
                      RankList(title: 'Top Rated', items: extras.topRated),
                    ),
                  if (bywShelves.isNotEmpty)
                    _gap('byw:0', ShelfRow(shelf: bywShelves.first)),
                  if (collection != null) ..._spotlight(context, collection),
                  for (final (i, s) in genreShelves.take(2).indexed)
                    _gap('genre:$i', ShelfRow(shelf: s)),
                  if (extras != null && extras.unwatchedTopRated.isNotEmpty)
                    _gap(
                      'unwatchedTopRated',
                      ShelfRow(
                        shelf: Shelf(
                          title: 'Highly Rated, Not Yet Watched',
                          items: extras.unwatchedTopRated,
                        ),
                      ),
                    ),
                  for (final (i, s) in bywShelves.skip(1).indexed)
                    _gap('byw:${i + 1}', ShelfRow(shelf: s)),
                  for (final (i, s) in genreShelves.skip(2).indexed)
                    _gap('genre:${i + 2}', ShelfRow(shelf: s)),
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
      return [_gap('spotlight', CollectionSpotlight.curated(pick, context))];
    }
    final spot = collection.spotlight;
    if (spot == null) return const [];
    return [
      _gap(
        'spotlight',
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

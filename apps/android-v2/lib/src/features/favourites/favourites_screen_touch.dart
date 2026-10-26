import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../data/models.dart';
import '../../navigation.dart';
import '../../ui/theme/soup_tokens.dart';
import '../../ui/touch/touch_scaffold.dart';
import '../../ui/touch/touch_widgets.dart';
import '../../ui/widgets/catalog_builder.dart';
import '../../ui/widgets/error_state.dart';
import '../../ui/widgets/glass_nav.dart' show NavSection;
import '../../ui/widgets/media_card.dart';
import '../../ui/widgets/pill_tabs.dart';
import '../../ui/widgets/select_menu.dart';
import 'favourites_screen.dart';
import 'my_stuff_tabs.dart';

/// Touch favourites: count and sort, type pills, then a poster grid.
class TouchFavouritesScreen extends StatefulWidget {
  const TouchFavouritesScreen({super.key});

  @override
  State<TouchFavouritesScreen> createState() => _TouchFavouritesScreenState();
}

class _TouchFavouritesScreenState extends State<TouchFavouritesScreen> {
  LibrarySort _sort = LibrarySort.title;
  FavouriteKind _kind = FavouriteKind.all;

  @override
  Widget build(BuildContext context) {
    final catalog = SoupScope.of(context).catalog;
    return CatalogBuilder<List<CatalogItem>>(
      load: (c) => c.favorites(_sort),
      keys: [_sort],
      builder: (context, loaded, error) => ValueListenableBuilder(
        valueListenable: catalog.favoriteOverrides,
        builder: (context, _, _) {
          final view = loaded == null
              ? null
              : FavouritesView(loaded, catalog.isFavorite, _kind);
          return TouchScaffold(
            section: NavSection.myStuff,
            title: 'My Stuff',
            slivers: [
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    TouchSpacing.gutter,
                    8,
                    TouchSpacing.gutter,
                    8,
                  ),
                  child: TouchMyStuffTabs(current: MyStuffTab.favourites),
                ),
              ),
              if (view != null && view.items.isNotEmpty)
                SliverToBoxAdapter(child: _header(view)),
              if (view == null && error != null)
                SliverToBoxAdapter(child: ErrorState(error: error))
              else if (view != null && view.items.isEmpty)
                SliverToBoxAdapter(child: _empty())
              else
                TouchPosterGrid(
                  itemCount: view?.visible.length ?? 12,
                  itemBuilder: (context, i, width) => view == null
                      ? MediaCardSkeleton(width: width)
                      : MediaCard(
                          key: ValueKey(view.visible[i].id),
                          item: view.visible[i],
                          width: width,
                        ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _header(FavouritesView view) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: TouchSpacing.gutter),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  view.countLabel,
                  style: SoupType.style(
                    size: 15,
                    weight: 600,
                    color: SoupColors.muted,
                  ),
                ),
              ),
              SelectMenu<LibrarySort>(
                prefix: 'Sort',
                surface: true,
                value: _sort,
                options: [
                  for (final s in favouriteSorts) SelectOption(s, s.label),
                ],
                onChanged: (s) => setState(() => _sort = s),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: TouchSpacing.gutter),
          child: PillTabs<FavouriteKind>(
            options: view.kinds,
            value: view.kind,
            labelOf: view.labelOf,
            onChanged: (k) => setState(() => _kind = k),
            height: 38,
          ),
        ),
      ],
    ),
  );

  Widget _empty() => Padding(
    padding: const EdgeInsets.fromLTRB(
      TouchSpacing.gutter,
      16,
      TouchSpacing.gutter,
      0,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'No favourites yet',
          style: SoupType.style(size: 20, weight: 800, letterSpacing: -0.5),
        ),
        const SizedBox(height: 8),
        Text(
          'Pick Add to Favourites under More on any movie, show or episode to keep it here.',
          style: SoupType.style(size: 15, color: SoupColors.muted),
        ),
        const SizedBox(height: 16),
        TouchButton(
          label: 'Browse Home',
          primary: false,
          onPressed: () => openHome(context),
        ),
      ],
    ),
  );
}

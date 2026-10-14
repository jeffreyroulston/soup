import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../data/models.dart';
import '../../form_factor.dart';
import '../../navigation.dart';
import '../../ui/theme/soup_tokens.dart';
import '../../ui/widgets/catalog_builder.dart';
import '../../ui/widgets/error_state.dart';
import '../../ui/widgets/glass_nav.dart';
import '../../ui/widgets/media_card.dart';
import '../../ui/widgets/page_scaffold.dart';
import '../../ui/widgets/pill_tabs.dart';
import '../../ui/widgets/select_menu.dart';
import '../../ui/widgets/soup_button.dart';
import 'favourites_screen_touch.dart';
import 'my_stuff_tabs.dart';

enum FavouriteKind {
  all('All', {}),
  movies('Movies', {'Movie'}),
  shows('Shows', {'Series'}),
  episodes('Episodes', {'Episode'});

  const FavouriteKind(this.label, this.types);
  final String label;
  final Set<String> types;

  bool matches(CatalogItem item) => types.isEmpty || types.contains(item.type);
}

/// Jellyfin keeps no "favourited on" date, so there's no "Recently
/// favourited"; Recently Added is library order.
const favouriteSorts = [
  LibrarySort.title,
  LibrarySort.recentlyAdded,
  LibrarySort.year,
];

/// What the page shows for one load: un-hearting applies at once (the
/// catalog's override), the type pills only offer types there are some of,
/// and a vanished type falls back to All.
class FavouritesView {
  FavouritesView(
    List<CatalogItem> loaded,
    bool Function(CatalogItem) isFavorite,
    FavouriteKind kind,
  ) : items = [
        for (final i in loaded)
          if (isFavorite(i)) i,
      ] {
    counts = {
      for (final k in FavouriteKind.values) k: items.where(k.matches).length,
    };
    kinds = [
      for (final k in FavouriteKind.values)
        if (k == FavouriteKind.all || counts[k]! > 0) k,
    ];
    this.kind = kinds.contains(kind) ? kind : FavouriteKind.all;
    visible = items.where(this.kind.matches).toList();
  }

  final List<CatalogItem> items;
  late final Map<FavouriteKind, int> counts;
  late final List<FavouriteKind> kinds;
  late final FavouriteKind kind;
  late final List<CatalogItem> visible;

  String get countLabel =>
      '${items.length} ${items.length == 1 ? 'title' : 'titles'}';

  String labelOf(FavouriteKind k) => '${k.label}  ${counts[k]}';
}

/// Web `pages/favourites.vue`: the My Stuff tab of favourite movies, shows
/// and episodes, with type pills and a sort.
class FavouritesScreen extends StatefulWidget {
  const FavouritesScreen({super.key});

  @override
  State<FavouritesScreen> createState() => _FavouritesScreenState();
}

class _FavouritesScreenState extends State<FavouritesScreen> {
  static const _minCardWidth = 176.0;
  static const _gap = 20.0;

  LibrarySort _sort = LibrarySort.title;
  FavouriteKind _kind = FavouriteKind.all;

  @override
  Widget build(BuildContext context) {
    if (context.isTouch) return const TouchFavouritesScreen();
    final catalog = SoupScope.of(context).catalog;
    final avail = MediaQuery.sizeOf(context).width - SoupSpacing.gutter * 2;
    final columns = ((avail + _gap) / (_minCardWidth + _gap)).floor().clamp(
      2,
      12,
    );
    final cardWidth = (avail - _gap * (columns - 1)) / columns;
    return CatalogBuilder<List<CatalogItem>>(
      load: (c) => c.favorites(_sort),
      keys: [_sort],
      builder: (context, loaded, error) => ValueListenableBuilder(
        valueListenable: catalog.favoriteOverrides,
        builder: (context, _, _) {
          final view = loaded == null
              ? null
              : FavouritesView(loaded, catalog.isFavorite, _kind);
          return PageScaffold(
            section: NavSection.myStuff,
            slivers: [
              SliverToBoxAdapter(child: _header(view)),
              SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: SoupSpacing.gutter,
                ),
                sliver: SliverToBoxAdapter(
                  child: _content(view, error, cardWidth),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Pills and sort get their own row under the title (not off to the
  /// right as on the web) so Up from the grid lands on them.
  Widget _header(FavouritesView? view) => Padding(
    padding: const EdgeInsets.fromLTRB(
      SoupSpacing.gutter,
      120,
      SoupSpacing.gutter,
      32,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const MyStuffHeader(current: MyStuffTab.favourites),
        if (view != null && view.items.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 28),
            child: Text(
              view.countLabel,
              style: SoupType.style(
                size: 16,
                weight: 600,
                color: SoupColors.muted,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              PillTabs<FavouriteKind>(
                options: view.kinds,
                value: view.kind,
                labelOf: view.labelOf,
                onChanged: (k) => setState(() => _kind = k),
              ),
              const SizedBox(width: 14),
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
        ],
      ],
    ),
  );

  Widget _content(FavouritesView? view, Object? error, double cardWidth) {
    if (view == null) {
      if (error != null) return ErrorState(error: error);
      return Wrap(
        spacing: _gap,
        runSpacing: 28,
        children: [
          for (var i = 0; i < 6; i++) MediaCardSkeleton(width: cardWidth),
        ],
      );
    }
    if (view.items.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No favourites yet',
            style: SoupType.style(size: 26, weight: 800, letterSpacing: -0.5),
          ),
          const SizedBox(height: 10),
          Text(
            'Pick Add to Favourites under More on any movie, show or episode to keep it here.',
            style: SoupType.style(size: 17, color: SoupColors.muted),
          ),
          const SizedBox(height: 22),
          SoupButton(
            label: 'Browse Home',
            autofocus: true,
            height: 48,
            style: SoupButtonStyle.glass,
            onPressed: () => openHome(context),
          ),
        ],
      );
    }
    return Wrap(
      spacing: _gap,
      runSpacing: 28,
      children: [
        for (var i = 0; i < view.visible.length; i++)
          MediaCard(
            key: ValueKey(view.visible[i].id),
            item: view.visible[i],
            width: cardWidth,
            autofocus: i == 0,
          ),
      ],
    );
  }
}

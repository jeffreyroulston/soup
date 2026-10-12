import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../navigation.dart';
import '../../ui/theme/soup_tokens.dart';
import '../../ui/touch/touch_scaffold.dart';
import '../../ui/touch/touch_widgets.dart';
import '../../ui/widgets/catalog_builder.dart';
import '../../ui/widgets/focusable.dart';
import '../../ui/widgets/glass_nav.dart' show NavSection;
import '../../ui/widgets/media_card.dart';
import '../../ui/widgets/pill_tabs.dart';
import '../../ui/widgets/select_menu.dart';
import 'library_filter.dart';

/// Touch library: library switcher, filters, sort, genre chips and a poster
/// grid (no A–Z strip; the grid flings instead).
class TouchLibraryScreen extends StatefulWidget {
  const TouchLibraryScreen({required this.library, super.key});
  final CatalogItem library;

  @override
  State<TouchLibraryScreen> createState() => _TouchLibraryScreenState();
}

class _TouchLibraryScreenState extends State<TouchLibraryScreen> {
  LibraryFilter _filter = LibraryFilter.all;
  LibrarySort _sort = LibrarySort.title;
  String? _genre;

  @override
  Widget build(BuildContext context) {
    final lib = widget.library;
    return CatalogBuilder<List<CatalogItem>>(
      load: (c) => c.libraryItems(lib, _sort),
      keys: [lib.id, _sort],
      builder: (context, all, error) {
        final items = all == null
            ? const <CatalogItem>[]
            : applyLibraryFilter(all, _filter, _genre);
        return TouchScaffold(
          section: NavSection.library,
          title: lib.name,
          slivers: [
            SliverToBoxAdapter(child: _header(lib)),
            if (error != null && all == null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(TouchSpacing.gutter),
                  child: Text(
                    'Could not load this library. $error',
                    style: SoupType.style(size: 15, color: SoupColors.accent),
                  ),
                ),
              )
            else if (all != null && items.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(TouchSpacing.gutter),
                  child: Text(
                    'Nothing matches these filters.',
                    style: SoupType.style(size: 15, color: SoupColors.muted),
                  ),
                ),
              )
            else
              TouchPosterGrid(
                itemCount: all == null ? 12 : items.length,
                itemBuilder: (context, i, width) => all == null
                    ? MediaCardSkeleton(width: width)
                    : MediaCard(item: items[i], width: width),
              ),
          ],
        );
      },
    );
  }

  Widget _header(CatalogItem lib) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CatalogBuilder<List<CatalogItem>>(
          load: (c) => c.libraries(),
          builder: (context, libraries, _) =>
              libraries == null || libraries.length < 2
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: TouchSpacing.gutter,
                    ),
                    child: PillTabs<String>(
                      options: [for (final l in libraries) l.id],
                      value: lib.id,
                      labelOf: (id) =>
                          libraries.firstWhere((l) => l.id == id).name,
                      onChanged: (id) => openLibrary(
                        context,
                        libraries.firstWhere((l) => l.id == id),
                      ),
                      height: 38,
                    ),
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: TouchSpacing.gutter),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CatalogBuilder<int>(
                      load: (c) => c.libraryTotal(lib),
                      keys: [lib.id],
                      builder: (context, total, _) => Padding(
                        padding: EdgeInsets.zero,
                        child: Text(
                          total == null ? '' : '$total titles',
                          style: SoupType.style(
                            size: 15,
                            weight: 600,
                            color: SoupColors.muted,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SelectMenu<LibrarySort>(
                prefix: 'Sort',
                surface: true,
                value: _sort,
                options: [
                  for (final s in LibrarySort.values) SelectOption(s, s.label),
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
          child: PillTabs<LibraryFilter>(
            options: LibraryFilter.values,
            value: _filter,
            labelOf: (f) => libraryFilterLabels[f]!,
            onChanged: (f) => setState(() => _filter = f),
            height: 38,
          ),
        ),
        CatalogBuilder<List<GenreCount>>(
          load: (c) => c.libraryGenres(lib),
          keys: [lib.id],
          builder: (context, genres, _) => genres == null || genres.isEmpty
              ? const SizedBox.shrink()
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(
                    TouchSpacing.gutter,
                    12,
                    TouchSpacing.gutter,
                    0,
                  ),
                  child: Row(
                    children: [
                      for (final g in genres)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _GenreChip(
                            label: g.name,
                            count: g.count,
                            selected: _genre == g.name,
                            onTap: () => setState(
                              () => _genre = _genre == g.name ? null : g.name,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    ),
  );
}

class _GenreChip extends StatelessWidget {
  const _GenreChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Focusable(
    radius: 17,
    scale: 1.0,
    onActivate: onTap,
    builder: (context, focused) => Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected
            ? SoupColors.ink
            : (focused ? SoupColors.elevated : SoupColors.surface),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Text(
        '$label  $count',
        style: SoupType.style(
          size: 13,
          weight: 700,
          color: selected ? SoupColors.canvas : SoupColors.ink2,
        ),
      ),
    ),
  );
}

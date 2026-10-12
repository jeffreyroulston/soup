import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../form_factor.dart';
import '../../ui/soup_focus_policy.dart';
import '../../ui/theme/soup_tokens.dart';
import '../../ui/widgets/catalog_builder.dart';
import '../../ui/widgets/focusable.dart';
import '../../ui/widgets/glass_nav.dart';
import '../../ui/widgets/media_card.dart';
import '../../ui/widgets/page_scaffold.dart';
import '../../ui/widgets/pill_tabs.dart';
import '../../ui/widgets/select_menu.dart';
import '../../utils/media.dart';
import 'library_filter.dart';
import 'library_screen_touch.dart';

const _tints = [
  Color(0xFF2541C8),
  Color(0xFF3A0F2A),
  Color(0xFF16353A),
  Color(0xFF5A3B22),
  Color(0xFF1F1A2E),
  Color(0xFF2E5E3B),
  Color(0xFF8A2A1E),
  Color(0xFF3A3F48),
];

/// Web `pages/library/[id].vue`: filter pills, sort, genre tiles, poster grid
/// and an A–Z jump strip.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({required this.library, super.key});
  final CatalogItem library;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  static const _cardWidth = 176.0;
  static const _gap = 20.0;
  static const _rowGap = 28.0;
  static const _captionHeight = 62.0;

  final _scroll = ScrollController();
  final _headerKey = GlobalKey();
  LibraryFilter _filter = LibraryFilter.all;
  LibrarySort _sort = LibrarySort.title;
  String? _genre;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<CatalogItem> _apply(List<CatalogItem> items) =>
      applyLibraryFilter(items, _filter, _genre);

  int _columns(double width) {
    final avail = width - SoupSpacing.gutter * 2 - 70; // A–Z strip
    return ((avail + _gap) / (_cardWidth + _gap)).floor().clamp(2, 12);
  }

  void _jump(String letter, List<CatalogItem> items, int columns) {
    final index = items.indexWhere((i) => sortLetter(i) == letter);
    if (index < 0 || !_scroll.hasClients) return;
    final box = _headerKey.currentContext?.findRenderObject() as RenderBox?;
    final header = box?.size.height ?? 300;
    final rowExtent = _cardWidth * 1.5 + _captionHeight + _rowGap;
    final target = header + (index ~/ columns) * rowExtent;
    _scroll.animateTo(
      target.clamp(0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (context.isTouch) return TouchLibraryScreen(library: widget.library);
    final lib = widget.library;
    final width = MediaQuery.sizeOf(context).width;
    final columns = _columns(width);
    return CatalogBuilder<List<CatalogItem>>(
      load: (c) => c.libraryItems(lib, _sort),
      keys: [lib.id, _sort],
      builder: (context, all, error) {
        final items = all == null ? const <CatalogItem>[] : _apply(all);
        final letters = {for (final i in items) sortLetter(i)};
        final rows = (items.length / columns).ceil();
        return PageScaffold(
          section: NavSection.library,
          libraryId: lib.id,
          controller: _scroll,
          overlay: all == null || items.isEmpty
              ? null
              : Positioned(
                  right: 16,
                  top: 110,
                  bottom: 40,
                  child: Center(
                    child: _AzStrip(
                      letters: letters,
                      onJump: (l) => _jump(l, items, columns),
                    ),
                  ),
                ),
          slivers: [
            SliverToBoxAdapter(
              child: KeyedSubtree(
                key: _headerKey,
                child: _Header(
                  library: lib,
                  filter: _filter,
                  sort: _sort,
                  genre: _genre,
                  onFilter: (f) => setState(() => _filter = f),
                  onSort: (s) => setState(() => _sort = s),
                  onGenre: (g) =>
                      setState(() => _genre = g == _genre ? null : g),
                ),
              ),
            ),
            if (error != null && all == null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(SoupSpacing.gutter),
                  child: Text(
                    'Could not load this library. $error',
                    style: SoupType.style(size: 17, color: SoupColors.accent),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.only(
                  left: SoupSpacing.gutter,
                  right: SoupSpacing.gutter + 70,
                ),
                sliver: SliverList.builder(
                  itemCount: all == null ? 3 : rows,
                  itemBuilder: (context, row) => Padding(
                    padding: const EdgeInsets.only(bottom: _rowGap),
                    child: SizedBox(
                      height: _cardWidth * 1.5 + _captionHeight,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var c = 0; c < columns; c++) ...[
                            if (all == null)
                              const MediaCardSkeleton(width: _cardWidth)
                            else if (row * columns + c < items.length)
                              MediaCard(
                                item: items[row * columns + c],
                                width: _cardWidth,
                                autofocus: row == 0 && c == 0,
                              )
                            else
                              const SizedBox(width: _cardWidth),
                            if (c < columns - 1) const SizedBox(width: _gap),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (all != null && items.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SoupSpacing.gutter,
                  ),
                  child: Text(
                    'Nothing matches these filters.',
                    style: SoupType.style(size: 17, color: SoupColors.muted),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.library,
    required this.filter,
    required this.sort,
    required this.genre,
    required this.onFilter,
    required this.onSort,
    required this.onGenre,
  });

  final CatalogItem library;
  final LibraryFilter filter;
  final LibrarySort sort;
  final String? genre;
  final ValueChanged<LibraryFilter> onFilter;
  final ValueChanged<LibrarySort> onSort;
  final ValueChanged<String> onGenre;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SoupSpacing.gutter,
        120,
        SoupSpacing.gutter + 70,
        28,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      library.name,
                      style: SoupType.style(
                        size: 56,
                        weight: 800,
                        letterSpacing: -2.5,
                        height: 1,
                      ),
                    ),
                    CatalogBuilder<int>(
                      load: (c) => c.libraryTotal(library),
                      keys: [library.id],
                      builder: (context, total, _) => Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          total == null ? '' : '$total titles',
                          style: SoupType.style(
                            size: 16,
                            weight: 600,
                            color: SoupColors.muted,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              PillTabs<LibraryFilter>(
                options: LibraryFilter.values,
                value: filter,
                labelOf: (f) => libraryFilterLabels[f]!,
                onChanged: onFilter,
              ),
              const SizedBox(width: 14),
              SelectMenu<LibrarySort>(
                prefix: 'Sort',
                surface: true,
                value: sort,
                options: [
                  for (final s in LibrarySort.values) SelectOption(s, s.label),
                ],
                onChanged: onSort,
              ),
            ],
          ),
          const SizedBox(height: 28),
          CatalogBuilder<List<GenreCount>>(
            load: (c) => c.libraryGenres(library),
            keys: [library.id],
            builder: (context, genres, _) => genres == null || genres.isEmpty
                ? const SizedBox.shrink()
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.hardEdge,
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 4,
                    ),
                    child: Row(
                      children: [
                        for (var i = 0; i < genres.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(right: 14),
                            child: Focusable(
                              radius: SoupRadii.card,
                              onActivate: () => onGenre(genres[i].name),
                              builder: (context, focused) => Container(
                                width: 168,
                                height: 76,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: _tints[i % _tints.length],
                                  borderRadius: BorderRadius.circular(
                                    SoupRadii.card,
                                  ),
                                  border: genre == genres[i].name
                                      ? Border.all(
                                          color: SoupColors.ink,
                                          width: 2,
                                        )
                                      : null,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      genres[i].name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: SoupType.style(
                                        size: 16,
                                        weight: 800,
                                      ),
                                    ),
                                    Text(
                                      '${genres[i].count}',
                                      style: SoupType.style(
                                        size: 12,
                                        weight: 600,
                                        color: SoupColors.ink2,
                                      ),
                                    ),
                                  ],
                                ),
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
}

class _AzStrip extends StatelessWidget {
  const _AzStrip({required this.letters, required this.onJump});
  final Set<String> letters;
  final ValueChanged<String> onJump;

  static const _all = [
    '#',
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'P',
    'Q',
    'R',
    'S',
    'T',
    'U',
    'V',
    'W',
    'X',
    'Y',
    'Z',
  ];

  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    padding: const EdgeInsets.symmetric(vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0x99282828),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0x1AFFFFFF)),
    ),
    child: FocusTraversalGroup(
      policy: SoupFocusPolicy(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final l in _all)
            if (letters.contains(l))
              Focusable(
                scale: 1.0,
                radius: 10,
                onActivate: () => onJump(l),
                builder: (context, focused) => Container(
                  width: 32,
                  height: 21,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: focused ? SoupColors.ink : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    l,
                    style: SoupType.style(
                      size: 13,
                      weight: 800,
                      color: focused ? SoupColors.canvas : SoupColors.ink2,
                    ),
                  ),
                ),
              )
            else
              SizedBox(
                width: 32,
                height: 21,
                child: Center(
                  child: Text(
                    l,
                    style: SoupType.style(
                      size: 13,
                      weight: 800,
                      color: const Color(0xFF48484A),
                    ),
                  ),
                ),
              ),
        ],
      ),
    ),
  );
}

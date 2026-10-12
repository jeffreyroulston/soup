import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models.dart';
import '../../form_factor.dart';
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
  static const _minCardWidth = 176.0;
  static const _gap = 20.0;
  static const _rowGap = 28.0;
  static const _captionHeight = 62.0;

  /// Right of the grid: the A–Z strip (40 wide, 16 from the edge) plus a gap.
  static const _stripReserve = 80.0;

  final _scroll = ScrollController();
  final _headerKey = GlobalKey();
  LibraryFilter _filter = LibraryFilter.all;
  LibrarySort _sort = LibrarySort.title;
  String? _genre;

  /// One node per A–Z letter, so the grid can hand focus to its letter.
  final _letterNodes = <String, FocusNode>{};

  /// The card a letter sends focus to (the first title under it).
  final _letterTarget = FocusNode(debugLabel: 'letter target');
  int? _letterTargetIndex;

  FocusNode _letterNode(String letter) => _letterNodes.putIfAbsent(
    letter,
    () => FocusNode(debugLabel: 'letter $letter'),
  );

  @override
  void dispose() {
    _scroll.dispose();
    _letterTarget.dispose();
    for (final node in _letterNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  List<CatalogItem> _apply(List<CatalogItem> items) =>
      applyLibraryFilter(items, _filter, _genre);

  /// As many columns of at least [_minCardWidth] as fit, then the cards
  /// stretch so the rows span the whole width up to the A–Z strip.
  static ({int columns, double cardWidth}) _grid(double width) {
    final avail = width - SoupSpacing.gutter - _stripReserve;
    final columns = ((avail + _gap) / (_minCardWidth + _gap)).floor().clamp(
      2,
      12,
    );
    return (
      columns: columns,
      cardWidth: (avail - _gap * (columns - 1)) / columns,
    );
  }

  static double _rowHeight(double cardWidth) =>
      cardWidth * 1.5 + _captionHeight;

  Future<void> _jump(
    String letter,
    List<CatalogItem> items,
    ({int columns, double cardWidth}) grid,
  ) async {
    final index = items.indexWhere((i) => sortLetter(i) == letter);
    if (index < 0 || !_scroll.hasClients) return;
    final box = _headerKey.currentContext?.findRenderObject() as RenderBox?;
    final header = box?.size.height ?? 300;
    final rowExtent = _rowHeight(grid.cardWidth) + _rowGap;
    final target = header + (index ~/ grid.columns) * rowExtent;
    await _scroll.animateTo(
      target.clamp(0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  /// Left/OK on a letter: into the grid at its first title.
  Future<void> _enterLetter(
    String letter,
    List<CatalogItem> items,
    ({int columns, double cardWidth}) grid,
  ) async {
    final index = items.indexWhere((i) => sortLetter(i) == letter);
    if (index < 0) return;
    setState(() => _letterTargetIndex = index);
    await _jump(letter, items, grid);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _letterTarget.context != null) {
        _letterTarget.requestFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (context.isTouch) return TouchLibraryScreen(library: widget.library);
    final lib = widget.library;
    final grid = _grid(MediaQuery.sizeOf(context).width);
    final columns = grid.columns;
    final cardWidth = grid.cardWidth;
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
                      focusNodeFor: _letterNode,
                      onFocus: (l) => unawaited(_jump(l, items, grid)),
                      onEnter: (l) => unawaited(_enterLetter(l, items, grid)),
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
                  right: _stripReserve,
                ),
                sliver: SliverList.builder(
                  itemCount: all == null ? 3 : rows,
                  itemBuilder: (context, row) => Padding(
                    padding: const EdgeInsets.only(bottom: _rowGap),
                    child: SizedBox(
                      height: _rowHeight(cardWidth),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var c = 0; c < columns; c++) ...[
                            if (all == null)
                              MediaCardSkeleton(width: cardWidth)
                            else if (row * columns + c < items.length)
                              _card(
                                items,
                                row * columns + c,
                                cardWidth,
                                // The row's last card hands Right to the
                                // strip, at its own letter.
                                rowEnd:
                                    c == columns - 1 ||
                                    row * columns + c == items.length - 1,
                              )
                            else
                              SizedBox(width: cardWidth),
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

  Widget _card(
    List<CatalogItem> items,
    int index,
    double width, {
    required bool rowEnd,
  }) {
    final item = items[index];
    final card = MediaCard(
      item: item,
      width: width,
      autofocus: index == 0,
      focusNode: index == _letterTargetIndex ? _letterTarget : null,
    );
    if (!rowEnd) return card;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is KeyUpEvent ||
            event.logicalKey != LogicalKeyboardKey.arrowRight) {
          return KeyEventResult.ignored;
        }
        _letterNode(sortLetter(item)).requestFocus();
        return KeyEventResult.handled;
      },
      child: card,
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

/// A–Z jump strip. Up/Down step through the letters that have titles and
/// stop at the ends; landing on a letter scrolls the grid to it, and Left/OK
/// moves into the grid at its first title.
class _AzStrip extends StatelessWidget {
  const _AzStrip({
    required this.letters,
    required this.focusNodeFor,
    required this.onFocus,
    required this.onEnter,
  });
  final Set<String> letters;
  final FocusNode Function(String letter) focusNodeFor;
  final ValueChanged<String> onFocus;
  final ValueChanged<String> onEnter;

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

  List<String> get _available => [
    for (final l in _all)
      if (letters.contains(l)) l,
  ];

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final available = _available;
    final current = available.indexWhere((l) => focusNodeFor(l).hasFocus);
    if (current < 0) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      final next = current + (key == LogicalKeyboardKey.arrowUp ? -1 : 1);
      if (next >= 0 && next < available.length) {
        focusNodeFor(available[next]).requestFocus();
      }
      // Stop at the ends rather than falling out into the grid or nav.
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft && event is KeyDownEvent) {
      onEnter(available[current]);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) return KeyEventResult.handled;
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    padding: const EdgeInsets.symmetric(vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0x99282828),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0x1AFFFFFF)),
    ),
    child: Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _key,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final l in _all)
            if (letters.contains(l))
              Focusable(
                focusNode: focusNodeFor(l),
                scale: 1.0,
                radius: 10,
                onFocusChange: (focused) {
                  if (focused) onFocus(l);
                },
                onActivate: () => onEnter(l),
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

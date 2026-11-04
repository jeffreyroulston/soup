import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../navigation.dart';
import '../../utils/media.dart';
import 'media_card.dart';
import 'media_row.dart';
import 'pill_tabs.dart';

/// Poster shelf (genres, because-you-watched). Episodes link to their series.
class ShelfRow extends StatelessWidget {
  const ShelfRow({required this.shelf, super.key});
  final Shelf shelf;

  @override
  Widget build(BuildContext context) => MediaRow(
    title: shelf.title,
    items: shelf.items,
    cardBuilder: (context, item, i) => MediaCard(
      item: item,
      favoriteButton: false,
      width: 200,
      onTap: () => item.type == 'Episode' && item.seriesId != null
          ? openItemId(context, item.seriesId!)
          : openItem(context, item),
    ),
  );
}

/// One "Recently Added" row with a pill switcher: All, then each library.
class RecentlyAddedRow extends StatefulWidget {
  const RecentlyAddedRow({required this.shelves, super.key});
  final List<Shelf> shelves;

  @override
  State<RecentlyAddedRow> createState() => _RecentlyAddedRowState();
}

class _RecentlyAddedRowState extends State<RecentlyAddedRow> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.shelves.isEmpty) return const SizedBox.shrink();
    final tabs = recentlyAddedTabs(widget.shelves);
    final i = _index.clamp(0, tabs.length - 1);
    final shelf = tabs[i];
    return MediaRow(
      railKey: ValueKey(shelf.libraryId),
      title: 'Recently Added',
      items: shelf.items,
      header: tabs.length > 1
          ? PillTabs<int>(
              options: [for (var k = 0; k < tabs.length; k++) k],
              value: i,
              labelOf: (k) => tabs[k].title,
              onChanged: (k) => setState(() => _index = k),
              height: 38,
            )
          : null,
      cardBuilder: (context, item, _) => MediaCard(
        item: item,
        favoriteButton: false,
        width: 200,
        onTap: () => item.type == 'Episode' && item.seriesId != null
            ? openItemId(context, item.seriesId!)
            : openItem(context, item),
      ),
    );
  }
}

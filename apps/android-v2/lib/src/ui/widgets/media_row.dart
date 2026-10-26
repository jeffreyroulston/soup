import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../theme/soup_tokens.dart';
import 'focusable.dart';
import 'media_card.dart';

/// Horizontal rail with a title, optional header widget and "See All".
/// Children are laid out eagerly (rows are short) so D-pad traversal always
/// finds the next card.
class MediaRow extends StatelessWidget {
  const MediaRow({
    required this.title,
    required this.items,
    this.shape = CardShape.poster,
    this.header,
    this.onSeeAll,
    this.loading = false,
    this.cardBuilder,
    this.slideWidth,
    this.autofocusFirst = false,
    this.railKey,
    super.key,
  });

  final String title;
  final List<CatalogItem> items;
  final CardShape shape;
  final Widget? header;
  final VoidCallback? onSeeAll;
  final bool loading;
  final Widget Function(BuildContext context, CatalogItem item, int index)?
  cardBuilder;
  final double? slideWidth;
  final bool autofocusFirst;

  /// Keys only the card rail, so swapping its items (e.g. a [header] tab)
  /// resets the scroll without rebuilding the header and losing its focus.
  final Key? railKey;

  double get _width => slideWidth ?? (shape == CardShape.poster ? 200 : 400);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: SoupSpacing.gutter),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SoupType.style(
                    size: 26,
                    weight: 800,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              if (header != null) ...[const SizedBox(width: 20), header!],
              const Spacer(),
              if (onSeeAll != null)
                Focusable(
                  onActivate: onSeeAll,
                  radius: 10,
                  builder: (context, focused) => Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Text(
                      'See All',
                      style: SoupType.style(
                        size: 16,
                        weight: 700,
                        color: focused ? SoupColors.ink : SoupColors.muted,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SingleChildScrollView(
          key: railKey,
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          padding: const EdgeInsets.symmetric(
            horizontal: SoupSpacing.gutter,
            vertical: 12,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (loading && items.isEmpty)
                for (var i = 0; i < 8; i++) ...[
                  MediaCardSkeleton(shape: shape, width: _width),
                  const SizedBox(width: 20),
                ]
              else
                for (var i = 0; i < items.length; i++) ...[
                  cardBuilder?.call(context, items[i], i) ??
                      MediaCard(
                        item: items[i],
                        shape: shape,
                        width: _width,
                        autofocus: autofocusFirst && i == 0,
                      ),
                  if (i < items.length - 1) const SizedBox(width: 20),
                ],
            ],
          ),
        ),
      ],
    );
  }
}

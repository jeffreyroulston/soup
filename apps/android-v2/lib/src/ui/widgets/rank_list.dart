import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../utils/media.dart';
import '../theme/soup_tokens.dart';
import 'media_card.dart';
import 'media_row.dart';

/// "Top Rated": wide cards with a big outlined rank numeral (web RankList).
class RankList extends StatelessWidget {
  const RankList({required this.title, required this.items, super.key});
  final String title;
  final List<CatalogItem> items;

  @override
  Widget build(BuildContext context) {
    return MediaRow(
      title: title,
      items: items,
      shape: CardShape.landscape,
      slideWidth: 460,
      cardBuilder: (context, item, i) => Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 64),
            child: MediaCard(
              item: item,
              shape: CardShape.landscape,
              width: 396,
              detail: [
                if (item.communityRating != null)
                  '★ ${item.communityRating!.toStringAsFixed(1)}',
                ?item.genres.firstOrNull,
                item.type,
                ?yearLabel(item),
              ].join(' · '),
            ),
          ),
          Positioned(left: 0, top: 40, child: _Rank(rank: i + 1)),
        ],
      ),
    );
  }
}

class _Rank extends StatelessWidget {
  const _Rank({required this.rank});
  final int rank;

  @override
  Widget build(BuildContext context) {
    final style = SoupType.style(
      size: 150,
      weight: 800,
      letterSpacing: -8,
      height: 1,
    );
    final first = rank == 1;
    return Stack(
      children: [
        Text(
          '$rank',
          style: style.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 8
              ..color = SoupColors.canvas,
          ),
        ),
        Text(
          '$rank',
          style: style.copyWith(
            foreground: Paint()
              ..shader = LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: first
                    ? [
                        SoupColors.accent,
                        SoupColors.accent.withValues(alpha: 0.08),
                      ]
                    : [
                        Colors.white.withValues(alpha: 0.85),
                        Colors.white.withValues(alpha: 0.08),
                      ],
              ).createShader(const Rect.fromLTWH(0, 0, 120, 150)),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../navigation.dart';
import '../theme/soup_tokens.dart';
import 'catalog_image.dart';
import 'focusable.dart';
import 'hero_carousel.dart';

/// Daily curated-collection card with diagonally cut posters (web
/// CollectionSpotlight). [title]/[items] come from a curated pack or a BoxSet.
class CollectionSpotlight extends StatelessWidget {
  const CollectionSpotlight({
    required this.title,
    required this.description,
    required this.countLabel,
    required this.items,
    required this.onOpen,
    super.key,
  });

  final String title;
  final String? description;
  final String countLabel;
  final List<CatalogItem> items;
  final VoidCallback onOpen;

  factory CollectionSpotlight.curated(
    CuratedCollection c,
    BuildContext context,
  ) => CollectionSpotlight(
    title: c.title,
    description: c.description,
    countLabel: c.countLabel,
    items: c.items,
    onOpen: () => openCollection(context, c.id),
  );

  @override
  Widget build(BuildContext context) {
    final withBackdrop = items.firstWhere(
      (i) => i.hasBackdrop,
      orElse: () => items.first,
    );
    final posters = items.take(4).toList();
    final width = MediaQuery.sizeOf(context).width;
    // Not one big target any more: each poster opens its film and the
    // button opens the collection (web CollectionSpotlight).
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SoupSpacing.gutter),
      child: SizedBox(
        height: 400,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(SoupRadii.spotlight),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CatalogImage(
                image: withBackdrop.backdrop,
                maxWidth: 1400,
                alignment: Alignment.topCenter,
              ),
              const ArtScrims(),
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                width: (width - SoupSpacing.gutter * 2) * 0.56,
                child: CollectionPosterStrip(posters: posters),
              ),
              Positioned(
                left: 40,
                bottom: 36,
                width: 520,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Collection · $countLabel',
                      style: SoupType.style(
                        size: 14,
                        weight: 700,
                        color: SoupColors.ink2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SoupType.style(
                        size: 50,
                        weight: 800,
                        letterSpacing: -2,
                        height: 0.95,
                      ),
                    ),
                    if (description != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: SoupType.style(
                          size: 16,
                          color: SoupColors.ink2,
                          height: 1.35,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Focusable(
                      radius: 23,
                      onActivate: onOpen,
                      builder: (context, focused) => Container(
                        height: 46,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: SoupColors.ink,
                          borderRadius: BorderRadius.circular(23),
                        ),
                        child: Text(
                          'Watch the collection',
                          style: SoupType.style(
                            size: 16,
                            weight: 800,
                            color: SoupColors.canvas,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-height posters cut on a diagonal, side by side; each opens its film.
/// The clip path is also the hit area and the focus outline, so a focused
/// poster never rings over its neighbours.
class CollectionPosterStrip extends StatelessWidget {
  const CollectionPosterStrip({required this.posters, super.key});
  final List<CatalogItem> posters;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final n = posters.length;
        if (n == 0) return const SizedBox.shrink();
        final w = constraints.maxWidth;
        final overlap = 0.035 * w;
        final each = (w + overlap * (n - 1)) / n;
        return Stack(
          children: [
            for (var i = 0; i < n; i++)
              Positioned(
                left: i * (each - overlap),
                width: each,
                top: 0,
                bottom: 0,
                child: _Poster(item: posters[i], last: i == n - 1),
              ),
          ],
        );
      },
    );
  }
}

class _Poster extends StatelessWidget {
  const _Poster({required this.item, required this.last});
  final CatalogItem item;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final clipper = _DiagonalClipper(last: last);
    return Semantics(
      button: true,
      label: item.name,
      child: ClipPath(
        clipper: clipper,
        child: Focusable(
          ring: false,
          scale: 1.0,
          onActivate: () => openItem(context, item),
          builder: (context, focused) => Stack(
            fit: StackFit.expand,
            children: [
              AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: focused ? 1 : 0.9,
                child: CatalogImage(
                  image: item.poster,
                  maxWidth: 400,
                  fallbackTitle: item.name,
                ),
              ),
              if (focused)
                IgnorePointer(
                  child: CustomPaint(painter: _OutlinePainter(clipper)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The diagonal clip's edge in ink, inset so the clip doesn't cut it.
class _OutlinePainter extends CustomPainter {
  const _OutlinePainter(this.clipper);
  final _DiagonalClipper clipper;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      clipper.getClip(size),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..color = SoupColors.ink,
    );
  }

  @override
  bool shouldRepaint(_OutlinePainter old) => old.clipper.last != clipper.last;
}

class _DiagonalClipper extends CustomClipper<Path> {
  const _DiagonalClipper({required this.last});
  final bool last;

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..moveTo(w * 0.14, 0)
      ..lineTo(w, 0)
      ..lineTo(last ? w : w * 0.86, h)
      ..lineTo(0, h)
      ..close();
  }

  @override
  bool shouldReclip(_DiagonalClipper old) => old.last != last;
}

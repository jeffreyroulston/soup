import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../data/models.dart';
import '../../form_factor.dart';
import '../../navigation.dart';
import '../../utils/media.dart';
import '../theme/soup_tokens.dart';
import 'catalog_image.dart';
import 'focusable.dart';

enum CardShape { poster, landscape }

/// Web MediaCard: art with watched badge + progress, caption underneath.
class MediaCard extends StatelessWidget {
  const MediaCard({
    required this.item,
    this.shape = CardShape.poster,
    this.width,
    this.kicker,
    this.detail,
    this.showPlay = false,
    this.autofocus = false,
    this.focusNode,
    this.onTap,
    this.titleOverride,
    this.favoriteButton = true,
    super.key,
  });

  final CatalogItem item;
  final CardShape shape;
  final double? width;
  final String? kicker;
  final String? detail;
  final bool showPlay;
  final bool autofocus;
  final FocusNode? focusNode;
  final VoidCallback? onTap;
  final String? titleOverride;

  /// Heart over the art's corner on favourites (web MediaCard). Home rows
  /// turn it off. On TV it's a badge only: a second focus target inside the
  /// card would fight the card's own focus ring.
  final bool favoriteButton;

  static const _favoriteTypes = {'Movie', 'Series', 'Episode'};

  @override
  Widget build(BuildContext context) {
    final poster = shape == CardShape.poster;
    final progress = isInProgress(item)
        ? (item.playedPercentage ?? 0) / 100
        : 0.0;
    final code = episodeCode(item);
    final detailText =
        detail ??
        (poster
            ? yearLabel(item)
            : (timeLeftLabel(item) ?? runtimeLabel(item.runTimeTicks)));
    final title =
        titleOverride ??
        (poster && item.type == 'Episode'
            ? (item.seriesName ?? item.name)
            : item.name);

    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Focusable(
            autofocus: autofocus,
            focusNode: focusNode,
            onActivate: onTap ?? () => openItem(context, item),
            builder: (context, focused) => AspectRatio(
              aspectRatio: poster ? 2 / 3 : 16 / 9,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(SoupRadii.card),
                  color: SoupColors.surface,
                  boxShadow: focused
                      ? const [
                          BoxShadow(
                            color: Color(0x8C000000),
                            blurRadius: 36,
                            offset: Offset(0, 16),
                          ),
                        ]
                      : null,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(SoupRadii.card),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CatalogImage(
                        image: poster ? item.poster : item.landscape,
                        maxWidth: poster ? 360 : 720,
                        fallbackTitle: item.name,
                      ),
                      if (item.played)
                        const Positioned(
                          top: 8,
                          right: 8,
                          child: _WatchedBadge(),
                        ),
                      if (favoriteButton && _favoriteTypes.contains(item.type))
                        Positioned(
                          top: 6,
                          left: 6,
                          child: _FavoriteBadge(item: item),
                        ),
                      if (showPlay && focused)
                        const Center(child: _PlayBadge()),
                      if (progress > 0)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: LinearProgressIndicator(
                            value: progress.clamp(0, 1),
                            minHeight: 4,
                            color: SoupColors.accent,
                            backgroundColor: const Color(0x66000000),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (kicker != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                kicker!.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SoupType.style(
                  size: 12,
                  weight: 700,
                  color: SoupColors.muted,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          if (!poster && code != null)
            Text(
              code,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SoupType.style(
                size: 13,
                weight: 600,
                color: SoupColors.muted,
              ),
            ),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SoupType.style(size: poster ? 15 : 16, weight: 700),
          ),
          if (poster && code != null)
            Text(
              code,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SoupType.style(
                size: 13,
                weight: 600,
                color: SoupColors.muted,
              ),
            ),
          if (detailText != null && !(poster && code != null))
            Text(
              detailText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SoupType.style(
                size: 13,
                weight: 600,
                color: SoupColors.muted,
              ),
            ),
        ],
      ),
    );
  }
}

class _FavoriteBadge extends StatelessWidget {
  const _FavoriteBadge({required this.item});
  final CatalogItem item;

  @override
  Widget build(BuildContext context) {
    final catalog = SoupScope.of(context).catalog;
    return ValueListenableBuilder(
      valueListenable: catalog.favoriteOverrides,
      builder: (context, _, _) {
        if (!catalog.isFavorite(item)) return const SizedBox.shrink();
        final badge = Container(
          width: 34,
          height: 34,
          decoration: const BoxDecoration(
            color: Color(0x8C0A0A0B),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.favorite_rounded,
            size: 19,
            color: SoupColors.accent,
          ),
        );
        if (!context.isTouch) return badge;
        return Semantics(
          button: true,
          label: 'Remove ${item.name} from favourites',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => catalog.setFavorite(item.id, false),
            child: Padding(padding: const EdgeInsets.all(2), child: badge),
          ),
        );
      },
    );
  }
}

class _WatchedBadge extends StatelessWidget {
  const _WatchedBadge();
  @override
  Widget build(BuildContext context) => Container(
    width: 26,
    height: 26,
    decoration: const BoxDecoration(
      color: Color(0x99000000),
      shape: BoxShape.circle,
    ),
    child: const Icon(Icons.check_rounded, size: 16, color: SoupColors.ink),
  );
}

class _PlayBadge extends StatelessWidget {
  const _PlayBadge();
  @override
  Widget build(BuildContext context) => Container(
    width: 56,
    height: 56,
    decoration: BoxDecoration(
      color: const Color(0x99282828),
      shape: BoxShape.circle,
      border: Border.all(color: const Color(0x33FFFFFF)),
    ),
    child: const Icon(
      Icons.play_arrow_rounded,
      size: 34,
      color: SoupColors.ink,
    ),
  );
}

/// Loading placeholder matching [MediaCard]'s box.
class MediaCardSkeleton extends StatelessWidget {
  const MediaCardSkeleton({
    this.shape = CardShape.poster,
    this.width,
    super.key,
  });
  final CardShape shape;
  final double? width;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: shape == CardShape.poster ? 2 / 3 : 16 / 9,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: SoupColors.surface,
              borderRadius: BorderRadius.circular(SoupRadii.card),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          height: 14,
          width: 110,
          decoration: BoxDecoration(
            color: SoupColors.surface,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ],
    ),
  );
}

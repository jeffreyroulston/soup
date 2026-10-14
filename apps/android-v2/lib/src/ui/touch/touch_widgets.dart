import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../data/models.dart';
import '../../navigation.dart';
import '../../utils/media.dart';
import '../theme/soup_tokens.dart';
import '../widgets/catalog_image.dart';
import '../widgets/focusable.dart';
import '../widgets/hero_carousel.dart' show ArtScrims, HeroSlide;
import '../widgets/media_card.dart';
import '../widgets/meta_line.dart';
import '../widgets/play_button.dart';
import '../widgets/title_art.dart';

/// Phone-sized counterparts of the TV spacing tokens.
abstract final class TouchSpacing {
  static const gutter = 16.0;
  static const rowGap = 28.0;
  static const posterWidth = 116.0;
  static const landscapeWidth = 248.0;
}

/// Section heading with an optional trailing widget (pills, "See all").
class TouchSectionTitle extends StatelessWidget {
  const TouchSectionTitle(this.title, {this.trailing, super.key});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: TouchSpacing.gutter),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SoupType.style(size: 20, weight: 800, letterSpacing: -0.4),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// Horizontal rail of cards under a [TouchSectionTitle].
class TouchRow extends StatelessWidget {
  const TouchRow({
    required this.title,
    required this.items,
    this.shape = CardShape.poster,
    this.cardBuilder,
    this.loading = false,
    this.header,
    this.trailing,
    super.key,
  });

  final String title;
  final List<CatalogItem> items;
  final CardShape shape;
  final Widget Function(BuildContext context, CatalogItem item, int index)?
  cardBuilder;
  final bool loading;

  /// Under the title, above the cards (e.g. season or library pills).
  final Widget? header;
  final Widget? trailing;

  double get _width => shape == CardShape.poster
      ? TouchSpacing.posterWidth
      : TouchSpacing.landscapeWidth;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TouchSectionTitle(title, trailing: trailing),
      if (header != null) ...[
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: TouchSpacing.gutter),
          child: header,
        ),
      ],
      const SizedBox(height: 10),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: TouchSpacing.gutter),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (loading && items.isEmpty)
              for (var i = 0; i < 6; i++) ...[
                MediaCardSkeleton(shape: shape, width: _width),
                const SizedBox(width: 12),
              ]
            else
              for (var i = 0; i < items.length; i++) ...[
                cardBuilder?.call(context, items[i], i) ??
                    MediaCard(item: items[i], shape: shape, width: _width),
                if (i < items.length - 1) const SizedBox(width: 12),
              ],
          ],
        ),
      ),
    ],
  );
}

/// Poster grid sized to the screen width (3 columns on a phone, more on a
/// tablet), with room for [MediaCard]'s two caption lines.
class TouchPosterGrid extends StatelessWidget {
  const TouchPosterGrid({
    required this.itemCount,
    required this.itemBuilder,
    super.key,
  });

  final int itemCount;
  final Widget Function(BuildContext context, int index, double width)
  itemBuilder;

  static const _gap = 12.0;

  @override
  Widget build(BuildContext context) {
    final captions = MediaQuery.textScalerOf(context).scale(44);
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: TouchSpacing.gutter),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          final available = constraints.crossAxisExtent;
          final columns =
              ((available + _gap) / (TouchSpacing.posterWidth + _gap))
                  .floor()
                  .clamp(3, 10);
          final width = (available - _gap * (columns - 1)) / columns;
          return SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: _gap,
              mainAxisSpacing: 18,
              mainAxisExtent: width * 1.5 + 10 + captions,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => itemBuilder(context, i, width),
              childCount: itemCount,
            ),
          );
        },
      ),
    );
  }
}

/// Primary (ink) or glass pill button sized for thumbs.
class TouchButton extends StatelessWidget {
  const TouchButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.primary = true,
    this.expand = false,
    this.height = 48,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool primary;
  final bool expand;
  final double height;

  @override
  Widget build(BuildContext context) => Focusable(
    radius: SoupRadii.button,
    onActivate: onPressed,
    builder: (context, focused) => Container(
      height: height,
      width: expand ? double.infinity : null,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: primary
            ? SoupColors.ink
            : (focused ? const Color(0xBF48484E) : const Color(0x99282828)),
        borderRadius: BorderRadius.circular(SoupRadii.button),
        border: primary ? null : Border.all(color: const Color(0x1AFFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 22,
              color: primary ? SoupColors.canvas : SoupColors.ink,
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SoupType.style(
                size: 16,
                weight: 800,
                color: primary ? SoupColors.canvas : SoupColors.ink,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Round glass icon button (favourite, watched, …).
class TouchIconButton extends StatelessWidget {
  const TouchIconButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.filled = false,
    this.color = SoupColors.ink,
    this.size = 48,
    super.key,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final bool filled;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: tooltip,
    child: Focusable(
      radius: size / 2,
      onActivate: onPressed,
      builder: (context, focused) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: filled
              ? SoupColors.ink
              : (focused ? const Color(0xBF48484E) : const Color(0x99282828)),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0x1AFFFFFF)),
        ),
        child: Icon(
          icon,
          size: size * 0.48,
          color: filled ? SoupColors.canvas : color,
        ),
      ),
    ),
  );
}

/// Small rounded metadata chip (rating, 4K, HDR…).
class TouchChip extends StatelessWidget {
  const TouchChip(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: const Color(0x33FFFFFF),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(label, style: SoupType.style(size: 11, weight: 800)),
  );
}

/// Swipeable featured carousel: backdrop, title, Play / Details / My List.
class TouchHero extends StatefulWidget {
  const TouchHero({required this.slides, this.loading = false, super.key});
  final List<HeroSlide> slides;
  final bool loading;

  @override
  State<TouchHero> createState() => _TouchHeroState();
}

class _TouchHeroState extends State<TouchHero> {
  final _pages = PageController();
  int _index = 0;
  Timer? _timer;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) {
      final n = widget.slides.length;
      if (_dragging || n < 2 || !_pages.hasClients) return;
      unawaited(
        _pages.animateToPage(
          (_index + 1) % n,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        ),
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final portrait = size.height > size.width;
    final height = portrait
        ? (size.width * 1.25).clamp(380.0, 620.0)
        : (size.height * 0.8).clamp(300.0, 560.0);
    if (widget.slides.isEmpty) {
      return SizedBox(
        height: height,
        child: widget.loading
            ? const ColoredBox(color: SoupColors.surface)
            : null,
      );
    }
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n is ScrollStartNotification && n.dragDetails != null) {
                _dragging = true;
              } else if (n is ScrollEndNotification) {
                _dragging = false;
              }
              return false;
            },
            child: PageView.builder(
              controller: _pages,
              itemCount: widget.slides.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) =>
                  _TouchSlide(slide: widget.slides[i], portrait: portrait),
            ),
          ),
          if (widget.slides.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 8,
              child: IgnorePointer(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < widget.slides.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: i == _index ? 20 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: i == _index
                              ? SoupColors.ink
                              : const Color(0x59FFFFFF),
                          borderRadius: BorderRadius.circular(3),
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

class _TouchSlide extends StatelessWidget {
  const _TouchSlide({required this.slide, required this.portrait});
  final HeroSlide slide;
  final bool portrait;

  @override
  Widget build(BuildContext context) {
    final item = slide.item;
    final scope = SoupScope.of(context);
    final isEpisode = item.type == 'Episode';
    final title = isEpisode ? (item.seriesName ?? item.name) : item.name;
    final meta = <String>[
      ?yearLabel(item),
      ?runtimeLabel(item.runTimeTicks),
      ...item.genres.take(2),
    ];
    final left = timeLeftLabel(item);
    final resume = item.isPlayable && left != null && canResume(item);
    return GestureDetector(
      onTap: () => openItem(context, item),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CatalogImage(
            // Portrait phones crop a backdrop badly; the poster fits.
            image: portrait ? item.poster : item.backdrop,
            maxWidth: portrait ? 720 : 1280,
            alignment: Alignment.topCenter,
            fallbackTitle: title,
          ),
          const ArtScrims(),
          Positioned(
            left: TouchSpacing.gutter,
            right: TouchSpacing.gutter,
            bottom: 28,
            child: Column(
              crossAxisAlignment: portrait
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TitleArt(
                  logo: item.logo,
                  maxWidth: 300,
                  maxHeight: 110,
                  alignment: portrait ? Alignment.center : Alignment.centerLeft,
                  fallback: Text(
                    title,
                    maxLines: 2,
                    textAlign: portrait ? TextAlign.center : TextAlign.start,
                    overflow: TextOverflow.ellipsis,
                    style: SoupType.style(
                      size: title.length > 24 ? 30 : 38,
                      weight: 800,
                      letterSpacing: -1.2,
                      height: 1,
                    ),
                  ),
                ),
                if (isEpisode && episodeCode(item) != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${episodeCode(item)}, ${item.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SoupType.style(
                      size: 14,
                      weight: 700,
                      color: SoupColors.ink2,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                MetaLine(
                  bits: meta,
                  size: 13,
                  spacing: 14,
                  alignment: portrait
                      ? WrapAlignment.center
                      : WrapAlignment.start,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: PlayButton(
                        compact: true,
                        height: 48,
                        label: !item.isPlayable
                            ? 'View'
                            : resume
                            ? 'Resume'
                            : 'Play',
                        icon: item.isPlayable,
                        detail: resume ? left : null,
                        progress: resume && isInProgress(item)
                            ? (item.playedPercentage ?? 0) / 100
                            : 0,
                        onActivate: () => item.isPlayable
                            ? openWatch(context, item)
                            : openItem(context, item),
                      ),
                    ),
                    // Phones open details by tapping the slide (web hides
                    // Details below `sm`).
                    if (!portrait) ...[
                      const SizedBox(width: 10),
                      Flexible(
                        child: TouchButton(
                          label: 'Details',
                          primary: false,
                          onPressed: () => openItem(context, item),
                        ),
                      ),
                    ],
                    const SizedBox(width: 10),
                    ValueListenableBuilder(
                      valueListenable: scope.catalog.favoriteOverrides,
                      builder: (context, _, _) {
                        final favorite = scope.catalog.isFavorite(item);
                        return TouchIconButton(
                          tooltip: favorite
                              ? 'Remove from favourites'
                              : 'Add to favourites',
                          icon: favorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: favorite ? SoupColors.accent : SoupColors.ink,
                          onPressed: () =>
                              scope.catalog.setFavorite(item.id, !favorite),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

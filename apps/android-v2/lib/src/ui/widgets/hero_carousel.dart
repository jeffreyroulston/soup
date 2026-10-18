import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../data/models.dart';
import '../../navigation.dart';
import '../../utils/media.dart';
import '../theme/soup_tokens.dart';
import 'catalog_image.dart';
import 'focusable.dart';
import 'meta_line.dart';
import 'play_button.dart';
import 'title_art.dart';

/// The two scrims the web lays over hero/spotlight art.
class ArtScrims extends StatelessWidget {
  const ArtScrims({super.key});

  @override
  Widget build(BuildContext context) => const Stack(
    fit: StackFit.expand,
    children: [
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [SoupColors.canvas, Color(0x990A0A0B), Color(0x000A0A0B)],
            stops: [0.0, 0.3, 0.6],
          ),
        ),
      ),
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0xB30A0A0B), Color(0x1A0A0B0B), Color(0x000A0A0B)],
            stops: [0.0, 0.45, 1.0],
          ),
        ),
      ),
    ],
  );
}

class HeroSlide {
  const HeroSlide(this.item);
  final CatalogItem item;
}

/// Auto-advancing featured carousel (web HeroCarousel).
class HeroCarousel extends StatefulWidget {
  const HeroCarousel({required this.slides, this.loading = false, super.key});
  final List<HeroSlide> slides;
  final bool loading;

  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel> {
  int _index = 0;
  bool _paused = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) {
      // TickerMode is off while another page covers Home (the player, an
      // item page), so the carousel doesn't keep rebuilding underneath.
      // valuesOf replaces this, but flutter-webOS (3.38) doesn't have it yet.
      // ignore: deprecated_member_use
      if (!mounted || !TickerMode.of(context)) return;
      if (!_paused && widget.slides.length > 1) {
        setState(() => _index = (_index + 1) % widget.slides.length);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _go(int delta) {
    final n = widget.slides.length;
    if (n < 2) return;
    setState(() => _index = (_index + delta + n) % n);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final height = (size.height * 0.88).clamp(560.0, 780.0);
    if (widget.slides.isEmpty) {
      return SizedBox(
        height: height,
        child: widget.loading
            ? const ColoredBox(color: SoupColors.surface)
            : null,
      );
    }
    if (_index >= widget.slides.length) _index = 0;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) => _paused = focused,
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Only the incoming and outgoing slides are built, so the other
            // full-screen backdrops aren't held decoded.
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 700),
              layoutBuilder: (current, previous) => Stack(
                fit: StackFit.expand,
                children: [
                  for (final child in previous)
                    ExcludeFocus(child: IgnorePointer(child: child)),
                  ?current,
                ],
              ),
              child: _Slide(
                key: ValueKey(widget.slides[_index].item.id),
                slide: widget.slides[_index],
                height: height,
                first: _index == 0,
              ),
            ),
            if (widget.slides.length > 1) ...[
              Positioned(
                right: SoupSpacing.gutter,
                bottom: 40,
                child: Row(
                  children: [
                    _RoundButton(
                      icon: Icons.chevron_left_rounded,
                      onTap: () => _go(-1),
                    ),
                    const SizedBox(width: 12),
                    _RoundButton(
                      icon: Icons.chevron_right_rounded,
                      onTap: () => _go(1),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 20,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < widget.slides.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: i == _index ? 28 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: i == _index
                              ? SoupColors.ink
                              : const Color(0x59FFFFFF),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Slide extends StatelessWidget {
  const _Slide({
    required this.slide,
    required this.height,
    required this.first,
    super.key,
  });
  final HeroSlide slide;
  final double height;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final item = slide.item;
    final scope = SoupScope.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final isEpisode = item.type == 'Episode';
    final title = isEpisode ? (item.seriesName ?? item.name) : item.name;
    final left = timeLeftLabel(item);
    final resume = item.isPlayable && left != null && canResume(item);
    final meta = <String>[
      ...item.genres.take(2),
      ?yearLabel(item),
      ?runtimeLabel(item.runTimeTicks),
    ];
    final badges = <String>[?item.officialRating, ...qualityBadges(item)];
    return Stack(
      fit: StackFit.expand,
      children: [
        CatalogImage(
          image: item.backdrop,
          maxWidth: 1600,
          alignment: Alignment.topCenter,
        ),
        const ArtScrims(),
        Positioned(
          left: SoupSpacing.gutter,
          right: SoupSpacing.gutter + 120,
          bottom: 84,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TitleArt(
                      logo: item.logo,
                      maxWidth: 520,
                      maxHeight: 190,
                      fallback: Text(
                        title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: SoupType.style(
                          size: heroTitleSize(title, width).clamp(40, 84),
                          weight: 800,
                          letterSpacing: -2.5,
                          height: 0.95,
                        ),
                      ),
                    ),
                    if (isEpisode && episodeCode(item) != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        '${episodeCode(item)}, ${item.name}',
                        style: SoupType.style(
                          size: 17,
                          weight: 700,
                          color: SoupColors.ink2,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    MetaLine(bits: meta, chips: badges),
                    if (item.overview != null && item.overview!.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        item.overview!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: SoupType.style(
                          size: 17,
                          color: SoupColors.ink2,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  PlayButton(
                    autofocus: first,
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
                  const SizedBox(width: 16),
                  Focusable(
                    radius: SoupRadii.button,
                    onActivate: () => openItem(context, item),
                    builder: (context, focused) => _GlassPill(
                      focused: focused,
                      child: Text(
                        'Details',
                        style: SoupType.style(size: 18, weight: 700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  ValueListenableBuilder(
                    valueListenable: scope.catalog.favoriteOverrides,
                    builder: (context, _, _) {
                      final favorite = scope.catalog.isFavorite(item);
                      return Focusable(
                        radius: SoupRadii.button,
                        onActivate: () =>
                            scope.catalog.setFavorite(item.id, !favorite),
                        builder: (context, focused) => _GlassPill(
                          focused: focused,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                favorite
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                size: 24,
                                color: favorite
                                    ? SoupColors.accent
                                    : SoupColors.ink,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Favourite',
                                style: SoupType.style(size: 18, weight: 700),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GlassPill extends StatelessWidget {
  const _GlassPill({required this.child, required this.focused});
  final Widget child;
  final bool focused;

  @override
  Widget build(BuildContext context) => Container(
    height: 56,
    padding: const EdgeInsets.symmetric(horizontal: 28),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: focused ? SoupColors.glassFocused : SoupColors.glass,
      borderRadius: BorderRadius.circular(SoupRadii.button),
      border: Border.all(color: SoupColors.faint),
    ),
    child: child,
  );
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Focusable(
    radius: 22,
    onActivate: onTap,
    builder: (context, focused) => Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: focused ? SoupColors.glassFocused : SoupColors.glass,
        shape: BoxShape.circle,
        border: Border.all(color: SoupColors.faint),
      ),
      child: Icon(icon, size: 26),
    ),
  );
}

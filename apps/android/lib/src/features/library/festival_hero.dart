import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:soup_core/src/legacy/artwork_cache.dart';
import 'package:soup_core/src/data/jellyfin/jellyfin_api.dart';
import 'package:soup/src/features/appearance/soup_theme.dart';
import 'package:soup/src/features/shared/artwork_placeholder.dart';
import 'package:soup/src/features/shared/fading_artwork.dart';

/// A printed programme beside the featured artwork. Copy determines the height,
/// so larger text never pushes the action outside a fixed hero viewport.
class FestivalHero extends StatelessWidget {
  const FestivalHero({
    required this.item,
    required this.userName,
    required this.image,
    required this.onOpen,
    this.focusNode,
    this.scrollFade = 0,
    super.key,
  });

  final JellyfinItem item;
  final String userName;
  final Future<CachedArtwork?> image;
  final VoidCallback onOpen;
  final FocusNode? focusNode;

  /// 0 at the top of the page; approaches 1 as home content scrolls away so the
  /// hero product softens into black.
  final double scrollFade;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final fade = scrollFade.clamp(0.0, 1.0);
    final artwork = Stack(
      fit: StackFit.expand,
      children: [
        FadingArtwork(
          artworkKey: '${item.id}:festival-backdrop',
          image: image,
          placeholder: ArtworkPlaceholder(blurHash: item.backdropBlurHash),
        ),
        DecoratedBox(
          key: const ValueKey('festival-hero-product-gradient'),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.18 + fade * 0.35),
                Colors.black.withValues(alpha: 0.72 + fade * 0.28),
              ],
              stops: const [0.42, 0.72, 1],
            ),
          ),
        ),
      ],
    );
    final copy = Container(
      key: const ValueKey('festival-hero-panel'),
      padding: EdgeInsets.all(wide ? 24 : 20),
      color: SoupTheme.onboardingAccent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${item.playbackPositionTicks > 0 ? 'UP NEXT' : 'NOW SHOWING'} FOR ${userName.toUpperCase()}',
            style: theme.textTheme.labelMedium?.copyWith(
              color: SoupTheme.onboardingSignal,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            item.name,
            key: const ValueKey('fruity-hero-title'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.displaySmall?.copyWith(
              color: SoupTheme.onboardingSurface,
              fontSize: wide ? 44 : 36,
            ),
          ),
          const SizedBox(height: 16),
          Container(width: 44, height: 4, color: SoupTheme.onboardingSignal),
          if (item.overview case final overview?) ...[
            const SizedBox(height: 12),
            Text(
              overview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: SoupTheme.onboardingSurface,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            key: const ValueKey('fruity-hero-open'),
            focusNode: focusNode,
            autofocus: true,
            onPressed: onOpen,
            // This action sits on cobalt in both brightness modes. A yellow
            // focus treatment remains distinct from the surrounding panel.
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.focused)
                    ? SoupTheme.onboardingSignal
                    : SoupTheme.onboardingInk,
              ),
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.focused)
                    ? SoupTheme.onboardingInk
                    : SoupTheme.onboardingSignal,
              ),
              side: const WidgetStatePropertyAll(
                BorderSide(color: SoupTheme.onboardingSignal, width: 2),
              ),
            ),
            icon: const Icon(PhosphorIconsRegular.arrowRight),
            label: const Text('View details'),
          ),
        ],
      ),
    );
    final product = wide
        ? LayoutBuilder(
            builder: (context, constraints) => Stack(
              children: [
                Positioned.fill(
                  left: constraints.maxWidth * 0.53,
                  child: artwork,
                ),
                SizedBox(width: constraints.maxWidth * 0.53, child: copy),
              ],
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(aspectRatio: 2, child: artwork),
              copy,
            ],
          );
    return Padding(
      padding: EdgeInsets.fromLTRB(wide ? 40 : 20, 24, wide ? 40 : 20, 32),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          boxShadow: [
            BoxShadow(color: SoupTheme.onboardingInk, offset: Offset(6, 6)),
          ],
        ),
        child: Stack(
          children: [
            product,
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  key: const ValueKey('festival-hero-scroll-blackout'),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: fade * 0.2),
                        Colors.black.withValues(alpha: fade * 0.55),
                        Colors.black.withValues(alpha: fade),
                      ],
                      stops: const [0, 0.55, 1],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

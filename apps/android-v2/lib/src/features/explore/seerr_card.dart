import 'package:flutter/material.dart';

import '../../data/seerr_models.dart';
import '../../navigation.dart';
import '../../ui/theme/soup_tokens.dart';
import '../../ui/touch/touch_widgets.dart';
import '../../ui/widgets/focusable.dart';
import '../../ui/widgets/media_card.dart';
import '../../ui/widgets/tmdb_image.dart';
import '../../utils/media.dart';

/// A Seerr title as a poster card, in [MediaCard]'s clothes, with its
/// library status in the corner (web `SeerrCard.vue`).
class SeerrCard extends StatelessWidget {
  const SeerrCard({
    required this.title,
    this.width,
    this.detail,
    this.autofocus = false,
    this.focusNode,
    super.key,
  });

  final SeerrTitle title;
  final double? width;

  /// Overrides the default secondary line (kind and year).
  final String? detail;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final availability = availabilityLabel(title.mediaInfo);
    final secondary =
        detail ??
        [
          title.mediaType.label,
          if (title.year != null) '${title.year}',
        ].join(', ');
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Focusable(
            autofocus: autofocus,
            focusNode: focusNode,
            semanticsLabel: [title.title, secondary, ?availability].join(', '),
            onActivate: () =>
                openExploreTitle(context, title.mediaType, title.tmdbId),
            builder: (context, focused) => AspectRatio(
              aspectRatio: 2 / 3,
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
                      TmdbImage(
                        path: title.posterPath,
                        kind: TmdbImageKind.poster,
                        alignment: Alignment.topCenter,
                        fallbackTitle: title.title,
                      ),
                      if (availability != null)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: SeerrStatusBadge(
                            tone: availabilityTone(title.mediaInfo)!,
                            label: availability,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SoupType.style(size: 15, weight: 700),
                ),
                Text(
                  secondary,
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
          ),
        ],
      ),
    );
  }
}

/// Green tick for titles in the library, orange clock for ones on their way.
class SeerrStatusBadge extends StatelessWidget {
  const SeerrStatusBadge({required this.tone, required this.label, super.key});
  final AvailabilityTone tone;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ok = tone == AvailabilityTone.ok || tone == AvailabilityTone.partial;
    return Semantics(
      label: label,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: switch (tone) {
            AvailabilityTone.ok => SoupColors.ok,
            AvailabilityTone.partial => const Color(0xB330D158),
            _ => SoupColors.accent,
          },
          shape: BoxShape.circle,
        ),
        child: Icon(
          ok ? Icons.check_rounded : Icons.schedule_rounded,
          size: ok ? 16 : 18,
          color: SoupColors.canvas,
        ),
      ),
    );
  }
}

/// TV rail of [SeerrCard]s, laid out like [MediaRow].
class SeerrRow extends StatelessWidget {
  const SeerrRow({
    required this.title,
    required this.titles,
    this.loading = false,
    this.onSeeAll,
    this.autofocusFirst = false,
    this.cardBuilder,
    super.key,
  });

  final String title;
  final List<SeerrTitle> titles;
  final bool loading;
  final VoidCallback? onSeeAll;
  final bool autofocusFirst;
  final Widget Function(BuildContext context, SeerrTitle title, int index)?
  cardBuilder;

  static const width = 200.0;

  @override
  Widget build(BuildContext context) => Column(
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
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: const EdgeInsets.symmetric(
          horizontal: SoupSpacing.gutter,
          vertical: 12,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (loading && titles.isEmpty)
              for (var i = 0; i < 8; i++) ...[
                const MediaCardSkeleton(width: width),
                const SizedBox(width: 20),
              ]
            else
              for (var i = 0; i < titles.length; i++) ...[
                cardBuilder?.call(context, titles[i], i) ??
                    SeerrCard(
                      title: titles[i],
                      width: width,
                      autofocus: autofocusFirst && i == 0,
                    ),
                if (i < titles.length - 1) const SizedBox(width: 20),
              ],
          ],
        ),
      ),
    ],
  );
}

/// Touch rail of [SeerrCard]s, laid out like [TouchRow].
class TouchSeerrRow extends StatelessWidget {
  const TouchSeerrRow({
    required this.title,
    required this.titles,
    this.loading = false,
    this.trailing,
    this.cardBuilder,
    super.key,
  });

  final String title;
  final List<SeerrTitle> titles;
  final bool loading;
  final Widget? trailing;
  final Widget Function(BuildContext context, SeerrTitle title, int index)?
  cardBuilder;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TouchSectionTitle(title, trailing: trailing),
      const SizedBox(height: 10),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: TouchSpacing.gutter),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (loading && titles.isEmpty)
              for (var i = 0; i < 6; i++) ...[
                const MediaCardSkeleton(width: TouchSpacing.posterWidth),
                const SizedBox(width: 12),
              ]
            else
              for (var i = 0; i < titles.length; i++) ...[
                cardBuilder?.call(context, titles[i], i) ??
                    SeerrCard(
                      title: titles[i],
                      width: TouchSpacing.posterWidth,
                    ),
                if (i < titles.length - 1) const SizedBox(width: 12),
              ],
          ],
        ),
      ),
    ],
  );
}

/// Round TMDB headshot with the name underneath; activating searches for
/// the person, which is how Seerr lists their titles.
class SeerrPersonCard extends StatelessWidget {
  const SeerrPersonCard({
    required this.person,
    required this.onActivate,
    this.size = 120,
    super.key,
  });

  final SeerrPerson person;
  final VoidCallback onActivate;
  final double size;

  @override
  Widget build(BuildContext context) {
    final knownFor = person.knownFor.take(2).map((t) => t.title).join(', ');
    return SizedBox(
      width: size + 10,
      child: Column(
        children: [
          Focusable(
            radius: size / 2,
            onActivate: onActivate,
            semanticsLabel: person.name,
            builder: (context, _) => ClipOval(
              child: SizedBox.square(
                dimension: size,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      color: SoupColors.elevated,
                      alignment: Alignment.center,
                      child: Text(
                        initials(person.name),
                        style: SoupType.style(
                          size: size * 0.27,
                          weight: 800,
                          color: SoupColors.muted,
                        ),
                      ),
                    ),
                    if (person.profilePath != null)
                      TmdbImage(
                        path: person.profilePath,
                        kind: TmdbImageKind.profile,
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            person.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: SoupType.style(size: 15, weight: 700),
          ),
          if (knownFor.isNotEmpty)
            Text(
              knownFor,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: SoupType.style(size: 12, color: SoupColors.muted),
            ),
        ],
      ),
    );
  }
}

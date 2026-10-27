import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/seerr.dart';
import '../../data/seerr_models.dart';
import '../../form_factor.dart';
import '../../navigation.dart';
import '../../ui/theme/soup_tokens.dart';
import '../../ui/widgets/focusable.dart';
import '../../ui/widgets/tmdb_image.dart';
import 'seerr_builder.dart';
import 'seerr_card.dart';

Color toneColor(AvailabilityTone tone) => switch (tone) {
  AvailabilityTone.ok || AvailabilityTone.partial => SoupColors.ok,
  AvailabilityTone.pending => SoupColors.accent,
  AvailabilityTone.declined => SoupColors.muted,
};

/// Status pill ("Pending approval", "In your library"…).
class SeerrStatusPill extends StatelessWidget {
  const SeerrStatusPill({
    required this.label,
    required this.tone,
    this.size = 13,
    super.key,
  });
  final String label;
  final AvailabilityTone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = toneColor(tone);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: size * 0.8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: SoupType.style(size: size, weight: 800, color: color),
      ),
    );
  }
}

/// One of the viewer's requests as a row: poster, title, status, what was
/// asked for and when, with Withdraw while it's still pending (web
/// `SeerrRequestCard.vue`). Activating the row opens the title.
class SeerrRequestCard extends StatefulWidget {
  const SeerrRequestCard({
    required this.request,
    this.autofocus = false,
    super.key,
  });

  final SeerrRequest request;
  final bool autofocus;

  @override
  State<SeerrRequestCard> createState() => _SeerrRequestCardState();
}

class _SeerrRequestCardState extends State<SeerrRequestCard> {
  bool _busy = false;
  String? _error;

  Future<void> _withdraw() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Seerr.of(context).cancelRequest(widget.request.id);
    } on Object catch (e) {
      if (mounted) {
        setState(
          () => _error = e is SeerrException
              ? e.message
              : "Couldn't withdraw the request.",
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final touch = context.isTouch;
    final status = requestStatusLabel(request);
    final posterWidth = touch ? 64.0 : 88.0;
    return SeerrBuilder<SeerrDetails?>(
      load: (s) => s.details(request.mediaType, request.tmdbId),
      keys: [request.mediaType, request.tmdbId],
      builder: (context, details, _) {
        final title =
            details?.title ?? '${request.mediaType.label} #${request.tmdbId}';
        final bits = <String>[
          request.mediaType.label,
          if (details?.year != null) '${details!.year}',
          ?seasonsLabel(request),
          if (shortDate(request.createdAt) case final date?) 'Requested $date',
        ];
        return Focusable(
          autofocus: widget.autofocus,
          radius: SoupRadii.panel,
          scale: 1.0,
          semanticsLabel: '$title, ${status.label}',
          onActivate: () =>
              openExploreTitle(context, request.mediaType, request.tmdbId),
          builder: (context, focused) => Container(
            padding: EdgeInsets.all(touch ? 12 : 16),
            decoration: BoxDecoration(
              color: focused ? SoupColors.elevated : SoupColors.surface,
              borderRadius: BorderRadius.circular(SoupRadii.panel),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: posterWidth,
                  height: posterWidth * 1.5,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: TmdbImage(
                      path: details?.posterPath,
                      kind: TmdbImageKind.poster,
                      fallbackTitle: details?.title,
                      fallbackFontSize: 12,
                      cacheWidth: 200,
                    ),
                  ),
                ),
                SizedBox(width: touch ? 12 : 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SoupType.style(
                          size: touch ? 16 : 19,
                          weight: 800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 10,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SeerrStatusPill(
                            label: status.label,
                            tone: status.tone,
                            size: touch ? 12 : 13,
                          ),
                          Text(
                            bits.join('  ·  '),
                            style: SoupType.style(
                              size: touch ? 12 : 14,
                              weight: 600,
                              color: SoupColors.muted,
                            ),
                          ),
                        ],
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          _error!,
                          style: SoupType.style(
                            size: 13,
                            weight: 600,
                            color: SoupColors.accent,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (request.isPending) ...[
                  SizedBox(width: touch ? 8 : 16),
                  _SmallButton(
                    label: _busy ? 'Withdrawing…' : 'Withdraw',
                    onActivate: _busy ? null : () => unawaited(_withdraw()),
                  ),
                ] else if (details?.mediaInfo?.jellyfinMediaId
                    case final id?) ...[
                  SizedBox(width: touch ? 8 : 16),
                  _SmallButton(
                    label: 'Watch',
                    primary: true,
                    onActivate: () => openItemId(context, id),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({
    required this.label,
    required this.onActivate,
    this.primary = false,
  });
  final String label;
  final VoidCallback? onActivate;
  final bool primary;

  @override
  Widget build(BuildContext context) => Focusable(
    radius: 18,
    scale: 1.0,
    onActivate: onActivate,
    builder: (context, focused) => Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: primary
            ? SoupColors.ink
            : (focused ? SoupColors.glassFocused : SoupColors.elevated),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        label,
        style: SoupType.style(
          size: 14,
          weight: 800,
          color: primary ? SoupColors.canvas : SoupColors.ink,
        ),
      ),
    ),
  );
}

/// A request as a poster tile for the Explore page's "Your Requests" rail:
/// the title's card with its request status as the caption.
class SeerrRequestTile extends StatelessWidget {
  const SeerrRequestTile({required this.request, this.width, super.key});
  final SeerrRequest request;
  final double? width;

  @override
  Widget build(BuildContext context) => SeerrBuilder<SeerrDetails?>(
    load: (s) => s.details(request.mediaType, request.tmdbId),
    keys: [request.mediaType, request.tmdbId],
    builder: (context, details, _) {
      final title =
          details ??
          SeerrTitle(
            tmdbId: request.tmdbId,
            mediaType: request.mediaType,
            title: '${request.mediaType.label} #${request.tmdbId}',
          );
      return SeerrCard(
        title: title,
        width: width,
        detail: requestStatusLabel(request).label,
      );
    },
  );
}

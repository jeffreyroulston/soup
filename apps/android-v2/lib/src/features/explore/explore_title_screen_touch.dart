import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/seerr.dart';
import '../../data/seerr_models.dart';
import '../../navigation.dart';
import '../../ui/theme/soup_tokens.dart';
import '../../ui/touch/touch_scaffold.dart';
import '../../ui/touch/touch_widgets.dart';
import '../../ui/widgets/expandable_overview.dart';
import '../../ui/widgets/glass_nav.dart' show NavSection;
import '../../ui/widgets/hero_carousel.dart' show ArtScrims;
import '../../ui/widgets/meta_line.dart';
import '../../ui/widgets/tmdb_image.dart';
import 'explore_gate.dart';
import 'explore_title_screen.dart';
import 'request_flow.dart';
import 'seerr_request_card.dart';
import 'seerr_unavailable.dart';

/// Touch title page: artwork under the top bar, then the facts, buttons,
/// overview, seasons and cast.
class TouchExploreTitleScreen extends StatelessWidget {
  const TouchExploreTitleScreen({
    required this.mediaType,
    required this.tmdbId,
    required this.flow,
    super.key,
  });

  final SeerrMediaType mediaType;
  final int tmdbId;
  final RequestFlow flow;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final loading = SizedBox(
      height: (width * 0.9).clamp(320.0, 520.0),
      child: const ColoredBox(color: SoupColors.surface),
    );
    return TouchScaffold(
      section: NavSection.none,
      title: mediaType.label,
      overlayTopBar: true,
      slivers: [
        SliverToBoxAdapter(
          child: ExploreGate(
            loading: loading,
            builder: (context, status) => TitleLoader(
              mediaType: mediaType,
              tmdbId: tmdbId,
              loading: loading,
              builder: (context, details) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Header(details: details),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      TouchSpacing.gutter,
                      16,
                      TouchSpacing.gutter,
                      0,
                    ),
                    child: ListenableBuilder(
                      listenable: flow,
                      builder: (context, _) => _Actions(
                        details: details,
                        status: status,
                        flow: flow,
                      ),
                    ),
                  ),
                  _Body(details: details),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.details});
  final SeerrDetails details;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final portrait = size.height > size.width;
    final usePoster = portrait || details.backdropPath == null;
    final availability = availabilityLabel(details.mediaInfo);
    return SizedBox(
      height: (size.width * 0.9).clamp(320.0, 520.0),
      child: Stack(
        fit: StackFit.expand,
        children: [
          TmdbImage(
            path: usePoster ? details.posterPath : details.backdropPath,
            kind: usePoster ? TmdbImageKind.poster : TmdbImageKind.backdrop,
            alignment: Alignment.topCenter,
            fallbackTitle: details.title,
          ),
          const ArtScrims(),
          Positioned(
            left: TouchSpacing.gutter,
            right: TouchSpacing.gutter,
            bottom: 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  details.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: SoupType.style(
                    size: details.title.length > 28 ? 28 : 36,
                    weight: 800,
                    letterSpacing: -1.2,
                    height: 1.02,
                  ),
                ),
                const SizedBox(height: 10),
                MetaLine(
                  bits: seerrMetaBits(details),
                  chips: [?details.contentRating],
                  size: 13,
                  spacing: 14,
                  color: SoupColors.muted,
                ),
                if (availability != null) ...[
                  const SizedBox(height: 10),
                  SeerrStatusPill(
                    label: availability,
                    tone: availabilityTone(details.mediaInfo)!,
                    size: 12,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.details,
    required this.status,
    required this.flow,
  });
  final SeerrDetails details;
  final SeerrStatus status;
  final RequestFlow flow;

  @override
  Widget build(BuildContext context) {
    final seerr = Seerr.of(context);
    final jellyfinId = details.mediaInfo?.jellyfinMediaId;
    final user = status.user;
    final allowed = user?.canRequest(details.mediaType) ?? false;
    final doneAlready = nothingToRequest(details.mediaInfo, details.seasons);
    final canRequest = user != null && allowed && !doneAlready;
    final trailer = details.trailerUrl == null
        ? null
        : Uri.tryParse(details.trailerUrl!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (jellyfinId != null)
              Expanded(
                child: TouchButton(
                  label: 'Watch in Soup',
                  icon: Icons.play_arrow_rounded,
                  onPressed: () => openItemId(context, jellyfinId),
                ),
              ),
            if (jellyfinId != null && canRequest) const SizedBox(width: 10),
            if (canRequest)
              Expanded(
                child: TouchButton(
                  label: flow.busy
                      ? 'Requesting…'
                      : details.isShow &&
                            RequestFlow.requestable(details).length > 1
                      ? 'Request seasons'
                      : 'Request',
                  icon: Icons.add_rounded,
                  primary: jellyfinId == null,
                  onPressed: flow.busy || flow.picking
                      ? null
                      : () => unawaited(flow.start(seerr, details)),
                ),
              ),
            if (trailer != null && (jellyfinId != null || canRequest))
              const SizedBox(width: 10),
            if (trailer != null)
              TouchIconButton(
                icon: Icons.theaters_outlined,
                tooltip: 'Watch trailer',
                onPressed: () => unawaited(
                  launchUrl(trailer, mode: LaunchMode.externalApplication),
                ),
              ),
          ],
        ),
        if (user == null) ...[
          const SizedBox(height: 12),
          const SeerrNotLinkedNote(),
        ] else if (!allowed) ...[
          const SizedBox(height: 12),
          Text(
            "Your Seerr account can't request "
            '${details.isShow ? 'shows' : 'movies'}.',
            style: SoupType.style(
              size: 13,
              weight: 600,
              color: SoupColors.muted,
            ),
          ),
        ],
        if (flow.picking) ...[
          const SizedBox(height: 14),
          SeasonPicker(
            details: details,
            flow: flow,
            compact: true,
            onSubmit: () => unawaited(flow.submitSelected(seerr, details)),
          ),
        ],
        if (flow.error case final error?) ...[
          const SizedBox(height: 12),
          Text(
            error,
            style: SoupType.style(
              size: 13,
              weight: 600,
              color: SoupColors.accent,
            ),
          ),
        ],
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.details});
  final SeerrDetails details;

  @override
  Widget build(BuildContext context) {
    final overview = details.overview;
    return Padding(
      padding: const EdgeInsets.fromLTRB(TouchSpacing.gutter, 20, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (details.tagline case final tagline? when tagline.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(
                bottom: 8,
                right: TouchSpacing.gutter,
              ),
              child: Text(
                tagline,
                style: SoupType.style(
                  size: 15,
                  weight: 700,
                  color: SoupColors.ink2,
                ),
              ),
            ),
          if (overview != null && overview.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: TouchSpacing.gutter),
              child: ExpandableOverview(
                text: overview,
                maxLines: 5,
                style: SoupType.style(
                  size: 15,
                  color: SoupColors.ink2,
                  height: 1.5,
                ),
              ),
            ),
          if (details.isShow && details.seasons.isNotEmpty) ...[
            const SizedBox(height: TouchSpacing.rowGap),
            Text(
              'Seasons',
              style: SoupType.style(size: 20, weight: 800, letterSpacing: -0.4),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: TouchSpacing.gutter),
              child: Column(
                children: [
                  for (final season in details.seasons)
                    SeasonRow(
                      season: season,
                      compact: true,
                      status: seasonStatusLabel(
                        seasonStatus(details.mediaInfo, season.seasonNumber),
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (details.cast.isNotEmpty) ...[
            const SizedBox(height: TouchSpacing.rowGap),
            CastRail(cast: details.cast, compact: true),
          ],
        ],
      ),
    );
  }
}

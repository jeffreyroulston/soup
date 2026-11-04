import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/seerr.dart';
import '../../data/seerr_models.dart';
import '../../form_factor.dart';
import '../../navigation.dart';
import '../../ui/theme/soup_tokens.dart';
import '../../ui/widgets/expandable_overview.dart';
import '../../ui/widgets/glass_nav.dart' show NavSection;
import '../../ui/widgets/hero_carousel.dart' show ArtScrims;
import '../../ui/widgets/meta_line.dart';
import '../../ui/widgets/page_scaffold.dart';
import '../../ui/widgets/soup_button.dart';
import '../../ui/widgets/tmdb_image.dart';
import '../../utils/media.dart';
import 'explore_gate.dart';
import 'explore_title_screen_touch.dart';
import 'request_flow.dart';
import 'seerr_builder.dart';
import 'seerr_request_card.dart';
import 'seerr_unavailable.dart';

/// A TMDB title from Seerr: artwork, facts, and Request / Watch in Soup
/// (web `pages/explore/[type]/[id].vue`).
class ExploreTitleScreen extends StatefulWidget {
  const ExploreTitleScreen({
    required this.mediaType,
    required this.tmdbId,
    super.key,
  });

  final SeerrMediaType mediaType;
  final int tmdbId;

  @override
  State<ExploreTitleScreen> createState() => _ExploreTitleScreenState();
}

class _ExploreTitleScreenState extends State<ExploreTitleScreen> {
  final _flow = RequestFlow();

  @override
  void dispose() {
    _flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (context.isTouch) {
      return TouchExploreTitleScreen(
        mediaType: widget.mediaType,
        tmdbId: widget.tmdbId,
        flow: _flow,
      );
    }
    return PageScaffold(
      section: NavSection.none,
      slivers: [
        SliverToBoxAdapter(
          child: ExploreGate(
            loading: const _Loading(),
            builder: (context, status) => TitleLoader(
              mediaType: widget.mediaType,
              tmdbId: widget.tmdbId,
              loading: const _Loading(),
              builder: (context, details) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Hero(details: details, status: status, flow: _flow),
                  _Body(details: details),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Loads a title's details, telling "not on TMDB" apart from "still
/// loading" and "failed". Shared by the TV and touch screens.
class TitleLoader extends StatelessWidget {
  const TitleLoader({
    required this.mediaType,
    required this.tmdbId,
    required this.loading,
    required this.builder,
    super.key,
  });

  final SeerrMediaType mediaType;
  final int tmdbId;
  final Widget loading;
  final Widget Function(BuildContext context, SeerrDetails details) builder;

  @override
  Widget build(BuildContext context) => SeerrBuilder<({SeerrDetails? details})>(
    load: (s) async => (details: await s.details(mediaType, tmdbId)),
    keys: [mediaType, tmdbId],
    builder: (context, data, error) {
      if (data == null && error == null) return loading;
      if (data == null) {
        return SeerrUnavailable(
          status: null,
          error: error,
          onRetry: () => Seerr.of(context).loadStatus(force: true).ignore(),
        );
      }
      final details = data.details;
      if (details == null) return const _NotFound();
      return builder(context, details);
    },
  );
}

class _NotFound extends StatelessWidget {
  const _NotFound();

  @override
  Widget build(BuildContext context) {
    final touch = context.isTouch;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: touch ? 24 : SoupSpacing.gutter,
        vertical: touch ? 48 : 120,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "This title isn't on TMDB",
            style: SoupType.style(
              size: touch ? 22 : 30,
              weight: 800,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'It may have been removed, or the link is wrong.',
            style: SoupType.style(
              size: touch ? 15 : 17,
              color: SoupColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return SizedBox(
      height: (size.height * 0.88).clamp(520.0, 720.0),
      child: const ColoredBox(color: SoupColors.surface),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.details,
    required this.status,
    required this.flow,
  });
  final SeerrDetails details;
  final SeerrStatus status;
  final RequestFlow flow;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final minHeight = (size.height * 0.88).clamp(0.0, 720.0);
    final availability = availabilityLabel(details.mediaInfo);
    return SizedBox(
      height: minHeight < 520 ? 520 : minHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          TmdbImage(
            path: details.backdropPath ?? details.posterPath,
            kind: details.backdropPath != null
                ? TmdbImageKind.backdrop
                : TmdbImageKind.poster,
            alignment: Alignment.topCenter,
            fallbackTitle: '',
          ),
          const ArtScrims(),
          Positioned(
            left: SoupSpacing.gutter,
            right: SoupSpacing.gutter,
            bottom: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        details.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: SoupType.style(
                          size: heroTitleSize(
                            details.title,
                            size.width,
                          ).clamp(40, 80),
                          weight: 800,
                          letterSpacing: -2.5,
                          height: 0.95,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 18,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          MetaLine(
                            bits: seerrMetaBits(details),
                            chips: [?details.contentRating],
                          ),
                          if (availability != null)
                            SeerrStatusPill(
                              label: availability,
                              tone: availabilityTone(details.mediaInfo)!,
                              size: 14,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                ListenableBuilder(
                  listenable: flow,
                  builder: (context, _) =>
                      _Actions(details: details, status: status, flow: flow),
                ),
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
    final String? note = user == null
        ? null
        : !allowed
        ? "Your Seerr account can't request "
              '${details.isShow ? 'shows' : 'movies'}.'
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (jellyfinId != null)
              SoupButton(
                label: 'Watch in Soup',
                icon: const Icon(Icons.play_arrow_rounded, size: 26),
                autofocus: true,
                onPressed: () => openItemId(context, jellyfinId),
              ),
            if (canRequest)
              SoupButton(
                label: flow.busy
                    ? 'Requesting…'
                    : details.isShow &&
                          RequestFlow.requestable(details).length > 1
                    ? 'Request seasons'
                    : 'Request',
                icon: const Icon(Icons.add_rounded, size: 24),
                style: jellyfinId == null
                    ? SoupButtonStyle.primary
                    : SoupButtonStyle.glass,
                autofocus: jellyfinId == null,
                onPressed: flow.busy || flow.picking
                    ? null
                    : () => unawaited(flow.start(seerr, details)),
              ),
          ],
        ),
        if (user == null) ...[
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: const SeerrNotLinkedNote(size: 15),
          ),
        ],
        if (note != null) ...[
          const SizedBox(height: 14),
          Text(
            note,
            style: SoupType.style(
              size: 15,
              weight: 600,
              color: SoupColors.muted,
            ),
          ),
        ],
        if (flow.picking) ...[
          const SizedBox(height: 18),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: SeasonPicker(
              details: details,
              flow: flow,
              onSubmit: () => unawaited(flow.submitSelected(seerr, details)),
            ),
          ),
        ],
        if (flow.error case final error?) ...[
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Text(
              error,
              style: SoupType.style(
                size: 15,
                weight: 600,
                color: SoupColors.accent,
              ),
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
      padding: const EdgeInsets.fromLTRB(SoupSpacing.gutter, 36, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (details.tagline case final tagline? when tagline.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(
                bottom: 12,
                right: SoupSpacing.gutter,
              ),
              child: Text(
                tagline,
                style: SoupType.style(
                  size: 19,
                  weight: 700,
                  color: SoupColors.ink2,
                ),
              ),
            ),
          if (overview != null && overview.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: ExpandableOverview(
                text: overview,
                style: SoupType.style(
                  size: 18,
                  color: SoupColors.ink2,
                  height: 1.5,
                ),
              ),
            ),
          if (details.isShow && details.seasons.isNotEmpty) ...[
            const SizedBox(height: SoupSpacing.rowGap),
            _Seasons(details: details),
          ],
          if (details.cast.isNotEmpty) ...[
            const SizedBox(height: SoupSpacing.rowGap),
            CastRail(cast: details.cast),
          ],
        ],
      ),
    );
  }
}

class _Seasons extends StatelessWidget {
  const _Seasons({required this.details});
  final SeerrDetails details;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Seasons',
        style: SoupType.style(size: 26, weight: 800, letterSpacing: -0.5),
      ),
      const SizedBox(height: 14),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Column(
          children: [
            for (final season in details.seasons)
              SeasonRow(
                season: season,
                status: seasonStatusLabel(
                  seasonStatus(details.mediaInfo, season.seasonNumber),
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

/// One season: name, episode count and air year, with its library status.
class SeasonRow extends StatelessWidget {
  const SeasonRow({
    required this.season,
    required this.status,
    this.compact = false,
    super.key,
  });
  final SeerrSeason season;
  final String? status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final bits = [
      '${season.episodeCount} ${season.episodeCount == 1 ? 'episode' : 'episodes'}',
      ?yearOf(season.airDate)?.toString(),
    ];
    return Container(
      margin: EdgeInsets.only(bottom: compact ? 8 : 10),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 18,
        vertical: compact ? 10 : 14,
      ),
      decoration: BoxDecoration(
        color: SoupColors.surface,
        borderRadius: BorderRadius.circular(SoupRadii.button),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  season.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SoupType.style(size: compact ? 15 : 17, weight: 800),
                ),
                Text(
                  bits.join('  ·  '),
                  style: SoupType.style(
                    size: compact ? 12 : 14,
                    weight: 600,
                    color: SoupColors.muted,
                  ),
                ),
              ],
            ),
          ),
          if (status != null)
            Text(
              status!,
              style: SoupType.style(
                size: compact ? 12 : 14,
                weight: 800,
                color: status == 'Requested' || status == 'On its way'
                    ? SoupColors.accent
                    : SoupColors.ok,
              ),
            ),
        ],
      ),
    );
  }
}

/// Cast as circular TMDB headshots with name and role.
class CastRail extends StatelessWidget {
  const CastRail({required this.cast, this.compact = false, super.key});
  final List<SeerrCastMember> cast;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 84.0 : 120.0;
    final gutter = compact ? 16.0 : SoupSpacing.gutter;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Cast',
          style: SoupType.style(
            size: compact ? 20 : 26,
            weight: 800,
            letterSpacing: -0.5,
          ),
        ),
        SizedBox(height: compact ? 10 : 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          padding: EdgeInsets.only(right: gutter),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final member in cast.take(20))
                Padding(
                  padding: EdgeInsets.only(right: compact ? 14 : 24),
                  child: SizedBox(
                    width: size,
                    child: Column(
                      children: [
                        ClipOval(
                          child: SizedBox(
                            width: size,
                            height: size,
                            child: TmdbImage(
                              path: member.profilePath,
                              kind: TmdbImageKind.profile,
                              fallbackTitle: initials(member.name),
                              fallbackFontSize: compact ? 20 : 28,
                              cacheWidth: 300,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          member.name,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: SoupType.style(
                            size: compact ? 13 : 15,
                            weight: 700,
                          ),
                        ),
                        if (member.character case final role?
                            when role.isNotEmpty)
                          Text(
                            role,
                            maxLines: 1,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: SoupType.style(
                              size: compact ? 12 : 13,
                              weight: 600,
                              color: SoupColors.muted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

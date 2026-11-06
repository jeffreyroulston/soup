import 'package:flutter/material.dart';

import '../../data/seerr_models.dart';
import '../../form_factor.dart';
import '../../navigation.dart';
import '../../ui/theme/soup_tokens.dart';
import '../../ui/widgets/focusable.dart';
import '../../ui/widgets/glass_nav.dart';
import '../../ui/widgets/page_scaffold.dart';
import 'explore_gate.dart';
import 'explore_screen_touch.dart';
import 'explore_tabs.dart';
import 'hidden_gems.dart';
import 'seerr_builder.dart';
import 'seerr_card.dart';
import 'seerr_request_card.dart';
import 'seerr_unavailable.dart';

/// The catalogue rows Discover shows.
const exploreRows = [
  (title: 'Trending', path: 'discover/trending'),
  (title: 'Popular Movies', path: 'discover/movies'),
  (title: 'Popular Shows', path: 'discover/tv'),
  (title: 'Coming Soon', path: 'discover/movies/upcoming'),
];

/// Web `pages/explore/index.vue`: trending/popular rows from Seerr's TMDB
/// catalogue, with the viewer's requests up top. Searching lives in Search.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final _tabFocus = FocusNode(debugLabel: 'explore tab');

  @override
  void dispose() {
    _tabFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (context.isTouch) {
      return const TouchExploreScreen();
    }
    return PageScaffold(
      section: NavSection.explore,
      entryFocus: _tabFocus,
      slivers: [
        SliverToBoxAdapter(
          child: ExploreGate(
            loading: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(
                    SoupSpacing.gutter,
                    120,
                    SoupSpacing.gutter,
                    40,
                  ),
                  child: ExploreHeader(current: ExploreTab.discover),
                ),
                for (var i = 0; i < 2; i++)
                  const Padding(
                    padding: EdgeInsets.only(bottom: SoupSpacing.rowGap),
                    child: SeerrRow(title: '', titles: [], loading: true),
                  ),
              ],
            ),
            builder: (context, status) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    SoupSpacing.gutter,
                    120,
                    SoupSpacing.gutter,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ExploreHeader(
                        current: ExploreTab.discover,
                        focusNode: _tabFocus,
                      ),
                      if (status.user == null) ...[
                        const SizedBox(height: 14),
                        const SeerrNotLinkedNote(size: 15),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 36),
                _Discover(status: status),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Discover extends StatelessWidget {
  const _Discover({required this.status});
  final SeerrStatus status;

  Widget _gap(String id, Widget child) => Padding(
    key: ValueKey(id),
    padding: const EdgeInsets.only(bottom: SoupSpacing.rowGap),
    child: child,
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (status.user != null)
        SeerrBuilder<SeerrRequestsPage>(
          load: (s) => s.myRequests(SeerrRequestFilter.all, take: 12),
          builder: (context, page, _) {
            final requests = page?.requests ?? const <SeerrRequest>[];
            if (requests.isEmpty) return const SizedBox.shrink();
            return _gap(
              'requests',
              _Rail(
                title: 'Your Requests',
                onSeeAll: () => openExploreRequests(context),
                children: [
                  for (final r in requests)
                    SeerrRequestTile(
                      key: ValueKey(r.id),
                      request: r,
                      width: SeerrRow.width,
                    ),
                ],
              ),
            );
          },
        ),
      for (final row in exploreRows) ...[
        SeerrBuilder<SeerrSearchResults>(
          load: (s) => s.discover(row.path),
          builder: (context, results, error) {
            if (error != null && results == null) {
              return const SizedBox.shrink();
            }
            return _gap(
              row.path,
              SeerrRow(
                title: row.title,
                titles: results?.titles ?? const [],
                loading: results == null,
              ),
            );
          },
        ),
        // The poster wall breaks up the rows, after Popular Shows.
        if (row.path == 'discover/tv')
          _gap('hidden gems', HiddenGemsWall(status: status)),
      ],
    ],
  );
}

/// A titled rail of arbitrary cards (the requests row).
class _Rail extends StatelessWidget {
  const _Rail({required this.title, required this.children, this.onSeeAll});
  final String title;
  final List<Widget> children;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: SoupSpacing.gutter),
        child: Row(
          children: [
            Text(
              title,
              style: SoupType.style(size: 26, weight: 800, letterSpacing: -0.5),
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
            for (var i = 0; i < children.length; i++) ...[
              children[i],
              if (i < children.length - 1) const SizedBox(width: 20),
            ],
          ],
        ),
      ),
    ],
  );
}

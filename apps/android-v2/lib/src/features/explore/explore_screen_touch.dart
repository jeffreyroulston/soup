import 'package:flutter/material.dart';

import '../../data/seerr_models.dart';
import '../../navigation.dart';
import '../../ui/theme/soup_tokens.dart';
import '../../ui/touch/touch_scaffold.dart';
import '../../ui/touch/touch_widgets.dart';
import '../../ui/widgets/focusable.dart';
import '../../ui/widgets/glass_nav.dart' show NavSection;
import 'explore_gate.dart';
import 'explore_screen.dart' show exploreRows;
import 'explore_tabs.dart';
import 'hidden_gems.dart';
import 'seerr_builder.dart';
import 'seerr_card.dart';
import 'seerr_request_card.dart';
import 'seerr_unavailable.dart';

/// Touch Explore: tabs up top, then the viewer's requests and the Seerr
/// discovery rails.
class TouchExploreScreen extends StatelessWidget {
  const TouchExploreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return TouchScaffold(
      section: NavSection.explore,
      title: 'Explore',
      slivers: [
        SliverToBoxAdapter(
          child: ExploreGate(
            loading: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(
                    TouchSpacing.gutter,
                    8,
                    TouchSpacing.gutter,
                    24,
                  ),
                  child: TouchExploreTabs(current: ExploreTab.discover),
                ),
                for (var i = 0; i < 2; i++)
                  const Padding(
                    padding: EdgeInsets.only(bottom: TouchSpacing.rowGap),
                    child: TouchSeerrRow(title: '', titles: [], loading: true),
                  ),
              ],
            ),
            builder: (context, status) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    TouchSpacing.gutter,
                    8,
                    TouchSpacing.gutter,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const TouchExploreTabs(current: ExploreTab.discover),
                      if (status.user == null) ...[
                        const SizedBox(height: 10),
                        const SeerrNotLinkedNote(),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
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
            return Padding(
              padding: const EdgeInsets.only(bottom: TouchSpacing.rowGap),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TouchSectionTitle(
                    'Your Requests',
                    trailing: _SeeAll(
                      onActivate: () => openExploreRequests(context),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: TouchSpacing.gutter,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < requests.length; i++) ...[
                          SeerrRequestTile(
                            key: ValueKey(requests[i].id),
                            request: requests[i],
                            width: TouchSpacing.posterWidth,
                          ),
                          if (i < requests.length - 1)
                            const SizedBox(width: 12),
                        ],
                      ],
                    ),
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
            return Padding(
              key: ValueKey(row.path),
              padding: const EdgeInsets.only(bottom: TouchSpacing.rowGap),
              child: TouchSeerrRow(
                title: row.title,
                titles: results?.titles ?? const [],
                loading: results == null,
              ),
            );
          },
        ),
        // The poster wall breaks up the rows, after Popular Shows.
        if (row.path == 'discover/tv')
          Padding(
            key: const ValueKey('hidden gems'),
            padding: const EdgeInsets.only(bottom: TouchSpacing.rowGap),
            child: HiddenGemsWall(status: status, touch: true),
          ),
      ],
    ],
  );
}

class _SeeAll extends StatelessWidget {
  const _SeeAll({required this.onActivate});
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) => Focusable(
    onActivate: onActivate,
    radius: 8,
    scale: 1.0,
    builder: (context, focused) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Text(
        'See all',
        style: SoupType.style(
          size: 14,
          weight: 700,
          color: focused ? SoupColors.ink : SoupColors.muted,
        ),
      ),
    ),
  );
}

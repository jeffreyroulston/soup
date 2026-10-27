import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/seerr.dart';
import '../../data/seerr_models.dart';
import '../../navigation.dart';
import '../../ui/theme/soup_tokens.dart';
import '../../ui/touch/touch_scaffold.dart';
import '../../ui/touch/touch_widgets.dart';
import '../../ui/widgets/focusable.dart';
import '../../ui/widgets/glass_nav.dart' show NavSection;
import '../../ui/widgets/soup_text_field.dart';
import 'explore_gate.dart';
import 'explore_screen.dart' show exploreRows;
import 'explore_tabs.dart';
import 'seerr_builder.dart';
import 'seerr_card.dart';
import 'seerr_request_card.dart';
import 'seerr_unavailable.dart';

/// Touch Explore: tabs and search field up top, then the viewer's requests
/// and the Seerr discovery rails, or search results.
class TouchExploreScreen extends StatefulWidget {
  const TouchExploreScreen({this.initialQuery, super.key});
  final String? initialQuery;

  @override
  State<TouchExploreScreen> createState() => _TouchExploreScreenState();
}

class _TouchExploreScreenState extends State<TouchExploreScreen> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialQuery ?? '',
  );
  Timer? _debounce;
  late String _term = (widget.initialQuery ?? '').trim();

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _changed(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _term = value.trim());
    });
  }

  void _setQuery(String value) {
    _controller.text = value;
    setState(() => _term = value.trim());
  }

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
                      const SizedBox(height: 12),
                      SoupTextField(
                        controller: _controller,
                        label: 'Search',
                        hint: 'Find a movie or show',
                        onChanged: _changed,
                        onSubmitted: () =>
                            setState(() => _term = _controller.text.trim()),
                      ),
                      if (status.user == null) ...[
                        const SizedBox(height: 10),
                        const SeerrNotLinkedNote(),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                if (_term.isEmpty)
                  _Discover(status: status)
                else
                  _Results(term: _term, onPerson: _setQuery),
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
      for (final row in exploreRows)
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

class _Results extends StatelessWidget {
  const _Results({required this.term, required this.onPerson});
  final String term;
  final ValueChanged<String> onPerson;

  static const _gap = 12.0;

  @override
  Widget build(BuildContext context) => SeerrBuilder<SeerrSearchResults>(
    load: (s) => s.search(term),
    keys: [term],
    builder: (context, results, error) {
      if (results == null && error == null) {
        return const TouchSeerrRow(
          title: 'Searching…',
          titles: [],
          loading: true,
        );
      }
      if (results == null) {
        return SeerrUnavailable(
          status: null,
          error: error,
          onRetry: () => Seerr.of(context).loadStatus(force: true).ignore(),
        );
      }
      if (results.isEmpty) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: TouchSpacing.gutter),
          child: Text(
            'Nothing matches “$term”.',
            style: SoupType.style(size: 15, color: SoupColors.muted),
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (results.titles.isNotEmpty) ...[
            const TouchSectionTitle('Movies & Shows'),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: TouchSpacing.gutter,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final available = constraints.maxWidth;
                  final columns =
                      ((available + _gap) / (TouchSpacing.posterWidth + _gap))
                          .floor()
                          .clamp(3, 10);
                  final width = (available - _gap * (columns - 1)) / columns;
                  return Wrap(
                    spacing: _gap,
                    runSpacing: 18,
                    children: [
                      for (final title in results.titles)
                        SeerrCard(
                          key: ValueKey(title.key),
                          title: title,
                          width: width,
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
          if (results.people.isNotEmpty) ...[
            const SizedBox(height: TouchSpacing.rowGap),
            const TouchSectionTitle('People'),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: TouchSpacing.gutter,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final p in results.people)
                    Padding(
                      padding: const EdgeInsets.only(right: 14),
                      child: SeerrPersonCard(
                        person: p,
                        size: 84,
                        onActivate: () => onPerson(p.name),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      );
    },
  );
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/seerr.dart';
import '../../data/seerr_models.dart';
import '../../form_factor.dart';
import '../../navigation.dart';
import '../../ui/theme/soup_tokens.dart';
import '../../ui/widgets/focusable.dart';
import '../../ui/widgets/glass_nav.dart';
import '../../ui/widgets/media_card.dart';
import '../../ui/widgets/page_scaffold.dart';
import '../../ui/widgets/soup_text_field.dart';
import 'explore_gate.dart';
import 'explore_screen_touch.dart';
import 'explore_tabs.dart';
import 'seerr_builder.dart';
import 'seerr_card.dart';
import 'seerr_request_card.dart';
import 'seerr_unavailable.dart';

/// The catalogue rows Discover shows when there's no search.
const exploreRows = [
  (title: 'Trending', path: 'discover/trending'),
  (title: 'Popular Movies', path: 'discover/movies'),
  (title: 'Popular Shows', path: 'discover/tv'),
  (title: 'Coming Soon', path: 'discover/movies/upcoming'),
];

/// Web `pages/explore/index.vue`: search Seerr's TMDB catalogue, or browse
/// trending/popular rows, with the viewer's requests up top.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({this.initialQuery, super.key});
  final String? initialQuery;

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialQuery ?? '',
  );
  Timer? _debounce;
  late String _term = (widget.initialQuery ?? '').trim();
  final _tabFocus = FocusNode(debugLabel: 'explore tab');

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _tabFocus.dispose();
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
    if (context.isTouch) {
      return TouchExploreScreen(initialQuery: widget.initialQuery);
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
                      const SizedBox(height: 28),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1000),
                        child: SoupTextField(
                          controller: _controller,
                          label: 'Search',
                          hint: 'Find a movie or show',
                          autofocus: true,
                          onChanged: _changed,
                          onSubmitted: () =>
                              setState(() => _term = _controller.text.trim()),
                        ),
                      ),
                      if (status.user == null) ...[
                        const SizedBox(height: 14),
                        const SeerrNotLinkedNote(size: 15),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 36),
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
      for (final row in exploreRows)
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

class _Results extends StatelessWidget {
  const _Results({required this.term, required this.onPerson});
  final String term;
  final ValueChanged<String> onPerson;

  static const _minCardWidth = 176.0;
  static const _gap = 20.0;

  @override
  Widget build(BuildContext context) {
    final avail = MediaQuery.sizeOf(context).width - SoupSpacing.gutter * 2;
    final columns = ((avail + _gap) / (_minCardWidth + _gap)).floor().clamp(
      2,
      12,
    );
    final cardWidth = (avail - _gap * (columns - 1)) / columns;
    return SeerrBuilder<SeerrSearchResults>(
      load: (s) => s.search(term),
      keys: [term],
      builder: (context, results, error) {
        if (results == null && error == null) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: SoupSpacing.gutter),
            child: Wrap(
              spacing: _gap,
              runSpacing: 28,
              children: [
                for (var i = 0; i < 6; i++) MediaCardSkeleton(width: cardWidth),
              ],
            ),
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
            padding: const EdgeInsets.symmetric(horizontal: SoupSpacing.gutter),
            child: Text(
              'Nothing matches “$term”.',
              style: SoupType.style(size: 17, color: SoupColors.muted),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (results.titles.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: SoupSpacing.gutter,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Movies & Shows',
                      style: SoupType.style(
                        size: 26,
                        weight: 800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: _gap,
                      runSpacing: 28,
                      children: [
                        for (final title in results.titles)
                          SeerrCard(
                            key: ValueKey(title.key),
                            title: title,
                            width: cardWidth,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            if (results.people.isNotEmpty) ...[
              const SizedBox(height: SoupSpacing.rowGap),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: SoupSpacing.gutter,
                ),
                child: Text(
                  'People',
                  style: SoupType.style(
                    size: 26,
                    weight: 800,
                    letterSpacing: -0.5,
                  ),
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
                    for (final p in results.people)
                      Padding(
                        padding: const EdgeInsets.only(right: 24),
                        child: SeerrPersonCard(
                          person: p,
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
}

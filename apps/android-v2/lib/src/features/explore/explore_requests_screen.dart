import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/seerr.dart';
import '../../data/seerr_models.dart';
import '../../form_factor.dart';
import '../../ui/theme/soup_tokens.dart';
import '../../ui/touch/touch_scaffold.dart';
import '../../ui/touch/touch_widgets.dart';
import '../../ui/widgets/glass_nav.dart' show NavSection;
import '../../ui/widgets/page_scaffold.dart';
import '../../ui/widgets/pill_tabs.dart';
import '../../ui/widgets/soup_button.dart';
import 'explore_gate.dart';
import 'explore_tabs.dart';
import 'seerr_builder.dart';
import 'seerr_request_card.dart';
import 'seerr_unavailable.dart';

const _pageSize = 20;

/// The viewer's Seerr requests, filtered by state and paged (web
/// `pages/explore/requests.vue`).
class ExploreRequestsScreen extends StatefulWidget {
  const ExploreRequestsScreen({super.key});

  @override
  State<ExploreRequestsScreen> createState() => _ExploreRequestsScreenState();
}

class _ExploreRequestsScreenState extends State<ExploreRequestsScreen> {
  SeerrRequestFilter _filter = SeerrRequestFilter.all;
  final _tabFocus = FocusNode(debugLabel: 'explore tab');

  @override
  void dispose() {
    _tabFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final touch = context.isTouch;
    final gutter = touch ? TouchSpacing.gutter : SoupSpacing.gutter;
    final body = ExploreGate(
      loading: Padding(
        padding: EdgeInsets.fromLTRB(gutter, touch ? 8 : 120, gutter, 0),
        child: touch
            ? const TouchExploreTabs(current: ExploreTab.requests)
            : const ExploreHeader(current: ExploreTab.requests),
      ),
      builder: (context, status) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(gutter, touch ? 8 : 120, gutter, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (touch)
                  const TouchExploreTabs(current: ExploreTab.requests)
                else
                  ExploreHeader(
                    current: ExploreTab.requests,
                    focusNode: _tabFocus,
                  ),
                SizedBox(height: touch ? 12 : 28),
                if (status.user != null)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    child: PillTabs<SeerrRequestFilter>(
                      options: SeerrRequestFilter.values,
                      value: _filter,
                      labelOf: (f) => f.label,
                      onChanged: (f) => setState(() => _filter = f),
                      height: touch ? 38 : 44,
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: touch ? 20 : 32),
          if (status.user == null)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: gutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No Seerr account yet',
                    style: SoupType.style(
                      size: touch ? 20 : 26,
                      weight: 800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SeerrNotLinkedNote(size: touch ? 14 : 16),
                ],
              ),
            )
          else
            _RequestList(
              key: ValueKey(_filter),
              filter: _filter,
              gutter: gutter,
              touch: touch,
            ),
        ],
      ),
    );
    if (touch) {
      return TouchScaffold(
        section: NavSection.explore,
        title: 'Explore',
        slivers: [SliverToBoxAdapter(child: body)],
      );
    }
    return PageScaffold(
      section: NavSection.explore,
      entryFocus: _tabFocus,
      slivers: [SliverToBoxAdapter(child: body)],
    );
  }
}

/// First page through [SeerrBuilder] (so it refreshes with the Seerr
/// revision); later pages are appended here and dropped when the data
/// behind them changes.
class _RequestList extends StatefulWidget {
  const _RequestList({
    required this.filter,
    required this.gutter,
    required this.touch,
    super.key,
  });
  final SeerrRequestFilter filter;
  final double gutter;
  final bool touch;

  @override
  State<_RequestList> createState() => _RequestListState();
}

class _RequestListState extends State<_RequestList> {
  final _extra = <SeerrRequest>[];
  int _extraPages = 0;
  int _revision = -1;
  bool _loadingMore = false;
  String? _moreError;

  Future<void> _loadMore(Seerr seerr) async {
    if (_loadingMore) return;
    setState(() {
      _loadingMore = true;
      _moreError = null;
    });
    try {
      final page = await seerr.myRequests(
        widget.filter,
        take: _pageSize,
        skip: _pageSize * (_extraPages + 1),
      );
      if (!mounted) return;
      setState(() {
        _extra.addAll(page.requests);
        _extraPages++;
      });
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _moreError = e is SeerrException
              ? e.message
              : "Couldn't load more requests.";
        });
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final seerr = Seerr.of(context);
    // A request was made or withdrawn: the first page reloads on its own,
    // the extra pages would be stale.
    if (seerr.revision != _revision) {
      _revision = seerr.revision;
      _extra.clear();
      _extraPages = 0;
    }
    final touch = widget.touch;
    return SeerrBuilder<SeerrRequestsPage>(
      load: (s) => s.myRequests(widget.filter, take: _pageSize),
      keys: [widget.filter],
      builder: (context, page, error) {
        if (page == null && error == null) {
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: widget.gutter),
            child: Column(
              children: [
                for (var i = 0; i < 3; i++)
                  Padding(
                    padding: EdgeInsets.only(bottom: touch ? 10 : 14),
                    child: Container(
                      height: touch ? 120 : 164,
                      decoration: BoxDecoration(
                        color: SoupColors.surface,
                        borderRadius: BorderRadius.circular(SoupRadii.panel),
                      ),
                    ),
                  ),
              ],
            ),
          );
        }
        if (page == null) {
          return SeerrUnavailable(
            status: null,
            error: error,
            onRetry: () => seerr.loadStatus(force: true).ignore(),
          );
        }
        final requests = [...page.requests, ..._extra];
        if (requests.isEmpty) {
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: widget.gutter),
            child: Text(
              widget.filter == SeerrRequestFilter.all
                  ? "You haven't requested anything yet. Find something "
                        'under Discover.'
                  : 'Nothing here.',
              style: SoupType.style(
                size: touch ? 15 : 17,
                color: SoupColors.muted,
              ),
            ),
          );
        }
        final shown = _pageSize * (_extraPages + 1);
        final more = page.total > shown && page.requests.length == _pageSize;
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: widget.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < requests.length; i++)
                Padding(
                  padding: EdgeInsets.only(bottom: touch ? 10 : 14),
                  child: SeerrRequestCard(
                    key: ValueKey(requests[i].id),
                    request: requests[i],
                    autofocus: !touch && i == 0,
                  ),
                ),
              if (_moreError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _moreError!,
                    style: SoupType.style(
                      size: 14,
                      weight: 600,
                      color: SoupColors.accent,
                    ),
                  ),
                ),
              if (more)
                touch
                    ? TouchButton(
                        label: _loadingMore ? 'Loading…' : 'Show more',
                        primary: false,
                        onPressed: _loadingMore
                            ? null
                            : () => unawaited(_loadMore(seerr)),
                      )
                    : SoupButton(
                        label: _loadingMore ? 'Loading…' : 'Show more',
                        style: SoupButtonStyle.glass,
                        onPressed: _loadingMore
                            ? null
                            : () => unawaited(_loadMore(seerr)),
                      ),
            ],
          ),
        );
      },
    );
  }
}

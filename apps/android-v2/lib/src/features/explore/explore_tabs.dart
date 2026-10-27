import 'package:flutter/material.dart';

import '../../navigation.dart';
import '../../ui/theme/soup_tokens.dart';
import '../../ui/widgets/focusable.dart';

/// The pages under Explore (web `ExploreHeader.vue`).
enum ExploreTab {
  discover('Discover'),
  requests('Requests');

  const ExploreTab(this.label);
  final String label;

  void open(BuildContext context) => switch (this) {
    ExploreTab.discover => openExplore(context),
    ExploreTab.requests => openExploreRequests(context),
  };
}

/// TV: the "Explore" title over underlined section tabs.
class ExploreHeader extends StatelessWidget {
  const ExploreHeader({required this.current, this.focusNode, super.key});

  final ExploreTab current;

  /// Attached to the [current] tab, so the page can make it the nav's
  /// landing spot.
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Explore',
          style: SoupType.style(
            size: 56,
            weight: 800,
            letterSpacing: -2.5,
            height: 1,
          ),
        ),
        const SizedBox(height: 18),
        DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0x26FFFFFF))),
          ),
          child: Row(
            children: [
              for (final tab in ExploreTab.values) ...[
                Focusable(
                  scale: 1.0,
                  radius: 10,
                  focusNode: tab == current ? focusNode : null,
                  onActivate: () {
                    if (tab != current) tab.open(context);
                  },
                  builder: (context, focused) => Container(
                    padding: const EdgeInsets.fromLTRB(8, 10, 8, 12),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: tab == current
                              ? SoupColors.accent
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                    child: Text(
                      tab.label,
                      style: SoupType.style(
                        size: 19,
                        weight: tab == current ? 800 : 700,
                        color: tab == current || focused
                            ? SoupColors.ink
                            : SoupColors.muted,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Phones and tablets: a full-width segmented switch under the top bar.
class TouchExploreTabs extends StatelessWidget {
  const TouchExploreTabs({required this.current, super.key});

  final ExploreTab current;

  static const _height = 44.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: SoupColors.surface,
        borderRadius: BorderRadius.circular(_height),
      ),
      child: Row(
        children: [
          for (final tab in ExploreTab.values)
            Expanded(
              child: Focusable(
                scale: 1.0,
                radius: _height,
                onActivate: () {
                  if (tab != current) tab.open(context);
                },
                builder: (context, focused) => Container(
                  height: _height - 8,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tab == current
                        ? SoupColors.ink
                        : (focused ? SoupColors.elevated : Colors.transparent),
                    borderRadius: BorderRadius.circular(_height),
                  ),
                  child: Text(
                    tab.label,
                    style: SoupType.style(
                      size: 14,
                      weight: 800,
                      color: tab == current
                          ? SoupColors.canvas
                          : SoupColors.muted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

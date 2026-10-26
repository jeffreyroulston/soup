import 'package:flutter/material.dart';

import '../../navigation.dart';
import '../../ui/theme/soup_tokens.dart';
import '../../ui/widgets/focusable.dart';

/// The pages under My Stuff (web `MyStuffHeader.vue`).
enum MyStuffTab {
  favourites('Favourites'),
  history('History');

  const MyStuffTab(this.label);
  final String label;

  void open(BuildContext context) => switch (this) {
    MyStuffTab.favourites => openFavourites(context),
    MyStuffTab.history => openHistory(context),
  };
}

/// TV: the "My Stuff" title over underlined section tabs.
class MyStuffHeader extends StatelessWidget {
  const MyStuffHeader({required this.current, super.key});

  final MyStuffTab current;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'My Stuff',
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
              for (final tab in MyStuffTab.values) ...[
                _UnderlineTab(
                  tab: tab,
                  selected: tab == current,
                  onActivate: () {
                    if (tab != current) tab.open(context);
                  },
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

class _UnderlineTab extends StatelessWidget {
  const _UnderlineTab({
    required this.tab,
    required this.selected,
    required this.onActivate,
  });

  final MyStuffTab tab;
  final bool selected;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    return Focusable(
      scale: 1.0,
      radius: 10,
      onActivate: onActivate,
      builder: (context, focused) => Container(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? SoupColors.accent : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Text(
          tab.label,
          style: SoupType.style(
            size: 19,
            weight: selected ? 800 : 700,
            color: selected || focused ? SoupColors.ink : SoupColors.muted,
          ),
        ),
      ),
    );
  }
}

/// Phones and tablets: a full-width segmented switch under the top bar.
class TouchMyStuffTabs extends StatelessWidget {
  const TouchMyStuffTabs({required this.current, super.key});

  final MyStuffTab current;

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
          for (final tab in MyStuffTab.values)
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

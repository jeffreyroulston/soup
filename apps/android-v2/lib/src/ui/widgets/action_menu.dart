import 'package:flutter/material.dart';

import '../../form_factor.dart';
import '../soup_focus_policy.dart';
import '../theme/soup_tokens.dart';
import 'focusable.dart';
import 'glass.dart';

class MenuAction {
  const MenuAction({
    required this.label,
    required this.icon,
    required this.onSelected,
    this.iconColor = SoupColors.ink,
  });
  final String label;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onSelected;
}

/// The item page's More menu: a centred glass list on TV, a bottom sheet on
/// touch. The chosen action runs after the menu has closed.
Future<void> showActionMenu(
  BuildContext context,
  List<MenuAction> actions,
) async {
  final picked = context.isTouch
      ? await showModalBottomSheet<MenuAction>(
          context: context,
          backgroundColor: const Color(0xF21E1E20),
          showDragHandle: true,
          builder: (sheet) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final a in actions)
                    ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      leading: Icon(a.icon, color: a.iconColor),
                      title: Text(
                        a.label,
                        style: SoupType.style(size: 16, weight: 600),
                      ),
                      onTap: () => Navigator.of(sheet).pop(a),
                    ),
                ],
              ),
            ),
          ),
        )
      : await showDialog<MenuAction>(
          context: context,
          barrierColor: const Color(0x99000000),
          builder: (dialog) => Center(
            child: SizedBox(
              width: 380,
              child: Glass(
                strong: true,
                radius: SoupRadii.menu,
                padding: const EdgeInsets.all(8),
                child: FocusTraversalGroup(
                  policy: SoupFocusPolicy(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < actions.length; i++)
                        // Rows sit flush, so the focused one inverts rather
                        // than ringing over its neighbours.
                        Focusable(
                          autofocus: i == 0,
                          scale: 1.0,
                          ring: false,
                          radius: 12,
                          onActivate: () =>
                              Navigator.of(dialog).pop(actions[i]),
                          builder: (context, focused) => Container(
                            height: 52,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: focused
                                  ? SoupColors.ink
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  actions[i].icon,
                                  size: 22,
                                  color:
                                      focused &&
                                          actions[i].iconColor == SoupColors.ink
                                      ? SoupColors.canvas
                                      : actions[i].iconColor,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(
                                    actions[i].label,
                                    style: SoupType.style(
                                      size: 17,
                                      weight: 600,
                                      color: focused
                                          ? SoupColors.canvas
                                          : SoupColors.ink,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
  picked?.onSelected();
}

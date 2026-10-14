import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../platform.dart';
import '../soup_focus_policy.dart';
import 'page_scaffold.dart';

/// Lays the app out on a fixed 1440×810 logical canvas and scales it to the
/// screen, so TVs with different pixel ratios (960×540, 1280×720, …) all look
/// like the web design.
class DesignScale extends StatelessWidget {
  const DesignScale({required this.child, super.key});

  static const designWidth = 1440.0;
  static const designHeight = 810.0;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return ColoredBox(
      color: videoBackdrop,
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: designWidth,
          height: designHeight,
          child: MediaQuery(
            data: media.copyWith(
              size: const Size(designWidth, designHeight),
              padding: EdgeInsets.zero,
              viewPadding: EdgeInsets.zero,
              viewInsets: EdgeInsets.zero,
            ),
            child: Shortcuts(
              // webOS: the remote's Back arrives as Escape and is replayed as
              // a route pop (installWebosBackKey), but Flutter still delivers
              // the key itself too, where Escape would dismiss an open menu
              // as well — one press, two pops.
              shortcuts: isWebos
                  ? const {
                      SingleActivator(LogicalKeyboardKey.escape):
                          DoNothingAndStopPropagationIntent(),
                    }
                  : const {},
              child: Actions(
                actions: {
                  DirectionalFocusIntent: _RecoveringDirectionalFocusAction(),
                },
                child: FocusTraversalGroup(
                  policy: SoupFocusPolicy(),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// D-pad moves, except that with focus lost (dropped, its widget gone, or
/// off-screen) an arrow lands on the current page's nav item instead.
class _RecoveringDirectionalFocusAction extends DirectionalFocusAction {
  @override
  void invoke(DirectionalFocusIntent intent) {
    if (PageScaffold.focusLost(primaryFocus) && PageScaffold.focusNav()) {
      return;
    }
    super.invoke(intent);
  }
}

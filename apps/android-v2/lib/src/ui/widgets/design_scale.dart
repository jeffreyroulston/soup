import 'package:flutter/material.dart';

import '../../platform.dart';
import '../soup_focus_policy.dart';

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
            child: FocusTraversalGroup(policy: SoupFocusPolicy(), child: child),
          ),
        ),
      ),
    );
  }
}

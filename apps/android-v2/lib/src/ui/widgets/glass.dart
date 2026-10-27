import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/soup_tokens.dart';

/// Frosted panel: web `.glass` (blur 24) and `.glass-strong` (blur 40).
class Glass extends StatelessWidget {
  const Glass({
    required this.child,
    this.strong = false,
    this.radius = SoupRadii.panel,
    this.padding,
    super.key,
  });

  final Widget child;
  final bool strong;
  final double radius;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    final sigma = strong ? 40.0 : 24.0;
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: strong
                ? const Color(0xD11E1E20) // rgb(30 30 32 / .82)
                : SoupColors.glass, // rgb(40 40 44 / .6)
            borderRadius: borderRadius,
            border: Border.all(color: SoupColors.faint),
          ),
          child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
        ),
      ),
    );
  }
}

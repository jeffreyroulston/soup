import 'package:flutter/material.dart';

import '../theme/soup_tokens.dart';
import 'focusable.dart';

enum SoupButtonStyle { primary, glass }

/// Web buttons: white `primary` (ink on canvas) and translucent `glass`.
class SoupButton extends StatelessWidget {
  const SoupButton({
    required this.label,
    required this.onPressed,
    this.style = SoupButtonStyle.primary,
    this.icon,
    this.autofocus = false,
    this.focusNode,
    this.height = 56,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final SoupButtonStyle style;
  final Widget? icon;
  final bool autofocus;
  final FocusNode? focusNode;
  final double height;

  @override
  Widget build(BuildContext context) {
    final primary = style == SoupButtonStyle.primary;
    return Focusable(
      autofocus: autofocus,
      focusNode: focusNode,
      onActivate: onPressed,
      radius: SoupRadii.button,
      builder: (context, focused) => Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 32),
        decoration: BoxDecoration(
          color: primary
              ? SoupColors.ink
              : (focused ? const Color(0xBF48484E) : const Color(0x99282828)),
          borderRadius: BorderRadius.circular(SoupRadii.button),
          border: primary ? null : Border.all(color: const Color(0x1AFFFFFF)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[icon!, const SizedBox(width: 10)],
            Text(
              label,
              style: SoupType.style(
                size: 19,
                weight: 800,
                color: primary ? SoupColors.canvas : SoupColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

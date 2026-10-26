import 'package:flutter/material.dart';

import '../../ui/theme/soup_tokens.dart';
import '../../ui/widgets/focusable.dart';
import '../../ui/widgets/soup_button.dart' show SoupButtonStyle;

/// Web button for the auth screens: white `primary` or translucent `glass`.
/// Unlike a plain button it takes an external [FocusNode] and, when
/// [onPressed] is null, is dimmed and inert.
class AuthButton extends StatelessWidget {
  const AuthButton({
    required this.label,
    required this.onPressed,
    this.style = SoupButtonStyle.primary,
    this.height = 56,
    this.focusNode,
    this.autofocus = false,
    this.expand = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final SoupButtonStyle style;
  final double height;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final primary = style == SoupButtonStyle.primary;
    final button = Opacity(
      opacity: onPressed == null ? 0.4 : 1,
      child: Focusable(
        focusNode: focusNode,
        autofocus: autofocus,
        onActivate: onPressed,
        radius: SoupRadii.button,
        builder: (context, focused) => Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 28),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: primary
                ? SoupColors.ink
                : (focused ? const Color(0xBF48484E) : const Color(0x99282828)),
            borderRadius: BorderRadius.circular(SoupRadii.button),
            border: primary ? null : Border.all(color: const Color(0x1AFFFFFF)),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SoupType.style(
              size: 18,
              weight: 800,
              color: primary ? SoupColors.canvas : SoupColors.ink,
            ),
          ),
        ),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

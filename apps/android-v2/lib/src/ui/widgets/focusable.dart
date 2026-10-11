import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/soup_tokens.dart';

/// Shared D-pad affordance: scale up and draw the web's focus ring
/// (3px ink outline, 3px offset) when focused; select/enter activates.
class Focusable extends StatefulWidget {
  const Focusable({
    required this.builder,
    this.onActivate,
    this.autofocus = false,
    this.focusNode,
    this.onFocusChange,
    this.scale = 1.03,
    this.radius = SoupRadii.card,
    super.key,
  });

  final Widget Function(BuildContext context, bool focused) builder;
  final VoidCallback? onActivate;
  final bool autofocus;
  final FocusNode? focusNode;
  final ValueChanged<bool>? onFocusChange;
  final double scale;
  final double radius;

  @override
  State<Focusable> createState() => _FocusableState();
}

class _FocusableState extends State<Focusable> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (value) {
        setState(() => _focused = value);
        widget.onFocusChange?.call(value);
        if (value) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
          );
        }
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            widget.onActivate != null &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
          widget.onActivate!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onActivate,
        child: AnimatedScale(
          scale: _focused ? widget.scale : 1,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius + 3),
              border: _focused
                  ? Border.all(color: SoupColors.ink, width: 3)
                  : null,
            ),
            child: widget.builder(context, _focused),
          ),
        ),
      ),
    );
  }
}

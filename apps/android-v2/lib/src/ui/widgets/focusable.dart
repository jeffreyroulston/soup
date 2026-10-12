import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../form_factor.dart';
import '../theme/soup_tokens.dart';

/// Shared D-pad affordance: scale up and draw the web's focus ring
/// (3px ink outline, 3px offset) when focused; select/enter activates.
///
/// On touch devices the ring and scale only show while a keyboard is driving
/// focus; taps get a press-down shrink instead.
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
  bool _pressed = false;

  /// Touch UI with no keyboard in use: focus is invisible.
  bool get _touchOnly =>
      context.isTouch &&
      FocusManager.instance.highlightMode == FocusHighlightMode.touch;

  void _press(bool value) {
    if (_pressed != value && widget.onActivate != null) {
      setState(() => _pressed = value);
    }
  }

  /// Scroll just enough to show the focused item with TV-friendly margins
  /// (clear of the top nav), instead of re-centring on every move.
  void _reveal() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    box.showOnScreen(
      rect: Rect.fromLTRB(
        -72,
        -150,
        box.size.width + 72,
        box.size.height + 110,
      ),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  /// Ink outline drawn outside the child with a canvas-coloured gap, so it
  /// reads on white fills (primary buttons, active pills) and on artwork.
  Widget _ring() => Positioned(
    left: -_ringOutset,
    top: -_ringOutset,
    right: -_ringOutset,
    bottom: -_ringOutset,
    child: IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius + _ringOutset),
          border: Border.all(color: SoupColors.ink, width: 3),
        ),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius + 3),
              border: Border.all(color: SoupColors.canvas, width: 3),
            ),
          ),
        ),
      ),
    ),
  );

  static const _ringOutset = 6.0;

  @override
  Widget build(BuildContext context) {
    final showFocus = _focused && !_touchOnly;
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (value) {
        setState(() => _focused = value);
        widget.onFocusChange?.call(value);
        if (value && !_touchOnly) _reveal();
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
        onTapDown: (_) => _press(true),
        onTapUp: (_) => _press(false),
        onTapCancel: () => _press(false),
        child: AnimatedScale(
          scale: _pressed ? 0.97 : (showFocus ? widget.scale : 1),
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          child: Stack(
            fit: StackFit.passthrough,
            clipBehavior: Clip.none,
            children: [
              widget.builder(context, showFocus),
              if (showFocus) _ring(),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../theme/soup_tokens.dart';
import 'focusable.dart';

/// Overview text clamped to [maxLines], with a More/Less toggle that appears
/// only when the clamp cuts it off.
class ExpandableOverview extends StatefulWidget {
  const ExpandableOverview({
    required this.text,
    required this.style,
    this.maxLines = 6,
    super.key,
  });
  final String text;
  final TextStyle style;
  final int maxLines;

  @override
  State<ExpandableOverview> createState() => _ExpandableOverviewState();
}

class _ExpandableOverviewState extends State<ExpandableOverview> {
  bool _open = false;

  @override
  void didUpdateWidget(ExpandableOverview old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _open = false;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final painter = TextPainter(
        text: TextSpan(text: widget.text, style: widget.style),
        maxLines: widget.maxLines,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: constraints.maxWidth);
      final clamped = painter.didExceedMaxLines;
      painter.dispose();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: Text(
              widget.text,
              maxLines: _open ? null : widget.maxLines,
              overflow: _open ? null : TextOverflow.ellipsis,
              style: widget.style,
            ),
          ),
          if (clamped)
            Focusable(
              radius: 8,
              scale: 1,
              onActivate: () => setState(() => _open = !_open),
              builder: (context, focused) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  _open ? 'Less' : 'More',
                  style:
                      SoupType.style(
                        size: 15,
                        weight: 800,
                        color: SoupColors.ink,
                      ).copyWith(
                        decoration: focused ? TextDecoration.underline : null,
                        decorationColor: SoupColors.ink,
                        decorationThickness: 2,
                      ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

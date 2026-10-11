import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../ui/theme/soup_tokens.dart';

/// Login backdrop: six tilted, slowly scrolling rows of public-domain posters
/// at 25% opacity, fading to canvas (web `PosterWall.vue`).
class PosterWall extends StatefulWidget {
  const PosterWall({super.key});

  static const posters = [
    'caligari',
    'charade',
    'gold-rush',
    'his-girl-friday',
    'metropolis',
    'night-of-the-living-dead',
    'phantom-of-the-opera',
    'safety-last',
    'sunrise',
    'the-general',
    'the-kid',
  ];

  @override
  State<PosterWall> createState() => _PosterWallState();
}

class _PosterWallState extends State<PosterWall> {
  static const _rows = 6;
  static const _perRow = 12;
  static const _durations = [90, 105, 120, 105, 90, 120];

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    const tileWidth = 176.0;
    const gap = 16.0;
    const tileHeight = tileWidth * 1.5;
    const halfExtent = _perRow * (tileWidth + gap);
    return ExcludeSemantics(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRect(
            child: Opacity(
              opacity: 0.25,
              child: OverflowBox(
                maxWidth: double.infinity,
                maxHeight: double.infinity,
                child: Transform.rotate(
                  angle: -6 * math.pi / 180,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var r = 0; r < _rows; r++) ...[
                        if (r > 0) const SizedBox(height: gap),
                        SizedBox(
                          height: tileHeight,
                          width: 3200,
                          child: _MarqueeRow(
                            animate: !reduced,
                            seconds: _durations[r],
                            reverse: r.isOdd,
                            halfExtent: halfExtent,
                            // Stagger the start so rows don't line up.
                            phase: r * 0.17,
                            children: [
                              for (var i = 0; i < _perRow * 2; i++)
                                _Tile(
                                  name:
                                      PosterWall.posters[(i % _perRow + r * 3) %
                                          PosterWall.posters.length],
                                  width: tileWidth,
                                  gap: gap,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                radius: 0.95,
                colors: [Color(0x000A0A0B), SoupColors.canvas],
                stops: [0.25, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MarqueeRow extends StatefulWidget {
  const _MarqueeRow({
    required this.animate,
    required this.seconds,
    required this.reverse,
    required this.halfExtent,
    required this.phase,
    required this.children,
  });

  final bool animate;
  final int seconds;
  final bool reverse;
  final double halfExtent;
  final double phase;
  final List<Widget> children;

  @override
  State<_MarqueeRow> createState() => _MarqueeRowState();
}

class _MarqueeRowState extends State<_MarqueeRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(seconds: widget.seconds),
    value: widget.phase,
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _controller.repeat();
  }

  @override
  void didUpdateWidget(_MarqueeRow old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.animate) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Painted once; only the translation changes per frame.
    final row = RepaintBoundary(
      child: OverflowBox(
        alignment: Alignment.centerLeft,
        maxWidth: double.infinity,
        child: Row(mainAxisSize: MainAxisSize.min, children: widget.children),
      ),
    );
    return AnimatedBuilder(
      animation: _controller,
      child: row,
      builder: (context, child) {
        final p = _controller.value;
        final dx = (widget.reverse ? p - 1 : -p) * widget.halfExtent;
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.name, required this.width, required this.gap});
  final String name;
  final double width;
  final double gap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(right: gap),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(SoupRadii.card),
      child: SizedBox(
        width: width,
        child: Image.asset(
          'assets/posters/$name.jpg',
          fit: BoxFit.cover,
          cacheWidth: 352,
          filterQuality: FilterQuality.low,
          errorBuilder: (_, _, _) =>
              const ColoredBox(color: SoupColors.surface),
        ),
      ),
    ),
  );
}

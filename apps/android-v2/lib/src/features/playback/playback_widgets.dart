import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:soup_core/soup_core.dart';

import '../../data/models.dart';
import '../../ui/theme/soup_tokens.dart';
import '../../ui/widgets/focusable.dart';
import '../../ui/widgets/glass.dart';
import '../../ui/widgets/soup_button.dart';

/// Round glass icon button (web 44–48px chrome buttons), D-pad focusable.
class ChromeButton extends StatelessWidget {
  const ChromeButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.size = 44,
    this.iconSize = 22,
    this.autofocus = false,
    this.focusNode,
    this.filled = false,
    this.busy = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final bool autofocus;
  final FocusNode? focusNode;
  final bool filled;

  /// Swap the icon for a spinner (play button while loading/buffering).
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Focusable(
        autofocus: autofocus,
        focusNode: focusNode,
        onActivate: onPressed,
        radius: size / 2,
        builder: (context, focused) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled
                ? SoupColors.ink
                : (focused ? SoupColors.glassFocused : SoupColors.glass),
            border: filled ? null : Border.all(color: SoupColors.faint),
          ),
          alignment: Alignment.center,
          child: busy
              ? SizedBox.square(
                  key: const ValueKey('chrome-button-busy'),
                  dimension: iconSize,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: filled ? SoupColors.canvas : SoupColors.ink,
                    backgroundColor: const Color(0x33FFFFFF),
                  ),
                )
              : Icon(
                  icon,
                  size: iconSize,
                  color: filled ? SoupColors.canvas : SoupColors.ink,
                ),
        ),
      ),
    );
  }
}

/// "Direct" (green dot) / "Transcode" (accent dot) pill from the web player.
class MethodPill extends StatelessWidget {
  const MethodPill({required this.method, super.key});
  final JellyfinPlayMethod method;

  @override
  Widget build(BuildContext context) {
    final direct = method != JellyfinPlayMethod.transcode;
    return Glass(
      radius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            key: const ValueKey('method-dot'),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: direct ? SoupColors.ok : SoupColors.accent,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            direct ? 'Direct' : 'Transcode',
            key: const ValueKey('playback-method'),
            style: SoupType.style(size: 13, weight: 700),
          ),
        ],
      ),
    );
  }
}

/// 8px (10 focused) seek bar: played layer, chapter ticks, Left/Right seek.
///
/// With [onScrub] it is also draggable: [onScrub] reports the position under
/// the finger while dragging (or on a tap) and [onScrubEnd] fires on release.
class SeekBar extends StatelessWidget {
  const SeekBar({
    required this.position,
    required this.duration,
    required this.chapterFractions,
    required this.onSeekBy,
    this.focusNode,
    this.onScrub,
    this.onScrubEnd,
    super.key,
  });

  final Duration position;
  final Duration duration;
  final List<double> chapterFractions;
  final void Function(Duration delta) onSeekBy;
  final FocusNode? focusNode;
  final ValueChanged<Duration>? onScrub;
  final VoidCallback? onScrubEnd;

  Duration _at(double dx, double width) =>
      width <= 0 ? Duration.zero : duration * (dx / width).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final total = duration.inMilliseconds;
    final fraction = total <= 0
        ? 0.0
        : (position.inMilliseconds / total).clamp(0.0, 1.0);
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          onSeekBy(const Duration(seconds: -10));
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          onSeekBy(const Duration(seconds: 10));
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final draggable = onScrub != null;
          final focused = Focus.of(context).hasFocus || draggable;
          final height = focused ? 10.0 : 8.0;
          return SizedBox(
            key: const ValueKey('playback-seekbar'),
            height: draggable ? 36 : 24,
            child: LayoutBuilder(
              builder: (context, c) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: draggable
                    ? (d) => onScrub!(_at(d.localPosition.dx, c.maxWidth))
                    : null,
                onTapUp: draggable ? (_) => onScrubEnd?.call() : null,
                onHorizontalDragStart: draggable
                    ? (d) => onScrub!(_at(d.localPosition.dx, c.maxWidth))
                    : null,
                onHorizontalDragUpdate: draggable
                    ? (d) => onScrub!(_at(d.localPosition.dx, c.maxWidth))
                    : null,
                onHorizontalDragEnd: draggable
                    ? (_) => onScrubEnd?.call()
                    : null,
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    Container(
                      height: height,
                      decoration: BoxDecoration(
                        color: const Color(0x33FFFFFF),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                    Container(
                      height: height,
                      width: c.maxWidth * fraction,
                      decoration: BoxDecoration(
                        color: SoupColors.ink,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                    for (final f in chapterFractions)
                      Positioned(
                        left: c.maxWidth * f - 1,
                        child: Container(
                          width: 2,
                          height: height,
                          color: const Color(0x99000000),
                        ),
                      ),
                    if (focused)
                      Positioned(
                        left: (c.maxWidth * fraction - 8).clamp(
                          0.0,
                          c.maxWidth - 16,
                        ),
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: SoupColors.ink,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The trickplay thumbnail at [position]: one cell of a sprite sheet, cropped
/// and scaled to [width]. Holds the last frame while the next sheet loads.
class TrickplayPreview extends StatefulWidget {
  const TrickplayPreview({
    required this.info,
    required this.position,
    required this.loadSheet,
    this.width = 200,
    super.key,
  });

  final Trickplay info;
  final Duration position;
  final Future<Uint8List?> Function(int index) loadSheet;
  final double width;

  @override
  State<TrickplayPreview> createState() => _TrickplayPreviewState();
}

class _TrickplayPreviewState extends State<TrickplayPreview> {
  Uint8List? _sheet;
  int? _sheetIndex;
  TrickplayFrame? _frame;
  int? _wanted;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(TrickplayPreview old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final frame = widget.info.frameAt(widget.position);
    if (frame.sheet == _sheetIndex) {
      _frame = frame;
      return;
    }
    if (_wanted == frame.sheet) return;
    _wanted = frame.sheet;
    unawaited(
      widget.loadSheet(frame.sheet).then((bytes) {
        if (!mounted || bytes == null || _wanted != frame.sheet) return;
        setState(() {
          _sheet = bytes;
          _sheetIndex = frame.sheet;
          _wanted = null;
          _frame = widget.info.frameAt(widget.position);
        });
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final scale = widget.width / info.width;
    final sheet = _sheet;
    final frame = _frame;
    final sheetWidth = info.sheetWidth * scale;
    final sheetHeight = info.sheetHeight * scale;
    // Decode near display size: a full sheet is ~3200×1800.
    final decodeWidth = (sheetWidth * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(1, info.sheetWidth);
    return Container(
      key: const ValueKey('trickplay-preview'),
      width: widget.width,
      height: info.height * scale,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x33FFFFFF)),
        boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 12)],
      ),
      child: sheet == null || frame == null
          ? null
          : OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: 0,
              minHeight: 0,
              maxWidth: sheetWidth,
              maxHeight: sheetHeight,
              child: Transform.translate(
                offset: Offset(-frame.x * scale, -frame.y * scale),
                child: Image.memory(
                  sheet,
                  width: sheetWidth,
                  height: sheetHeight,
                  cacheWidth: decodeWidth,
                  fit: BoxFit.fill,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ),
    );
  }
}

/// "Skip intro / recap / credits" pill.
class SkipButton extends StatelessWidget {
  const SkipButton({required this.label, required this.onPressed, super.key});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SoupButton(
    label: label,
    onPressed: onPressed,
    height: 44,
    icon: const Icon(
      Icons.skip_next_rounded,
      size: 22,
      color: SoupColors.canvas,
    ),
  );
}

/// Countdown card for the next episode.
class NextEpisodeCard extends StatelessWidget {
  const NextEpisodeCard({
    required this.title,
    required this.seconds,
    required this.onPlayNow,
    required this.onCancel,
    super.key,
  });

  final String title;
  final int seconds;
  final VoidCallback onPlayNow;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 320,
    child: Glass(
      strong: true,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Next episode in $seconds',
            key: const ValueKey('next-episode-countdown'),
            style: SoupType.style(
              size: 12,
              weight: 800,
              color: SoupColors.muted,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: SoupType.style(size: 17, weight: 800),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _CardButton(
                  label: 'Play now',
                  primary: true,
                  autofocus: true,
                  onPressed: onPlayNow,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: _CardButton(label: 'Cancel', onPressed: onCancel),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _CardButton extends StatelessWidget {
  const _CardButton({
    required this.label,
    required this.onPressed,
    this.primary = false,
    this.autofocus = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool primary;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Focusable(
    autofocus: autofocus,
    onActivate: onPressed,
    radius: SoupRadii.button,
    builder: (context, focused) => Container(
      height: 42,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: primary
            ? SoupColors.ink
            : (focused ? SoupColors.glassFocused : SoupColors.glass),
        borderRadius: BorderRadius.circular(SoupRadii.button),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          style: SoupType.style(
            size: 15,
            weight: 800,
            color: primary ? SoupColors.canvas : SoupColors.ink,
          ),
        ),
      ),
    ),
  );
}

class PlaybackError extends StatefulWidget {
  const PlaybackError({
    required this.error,
    required this.onRetry,
    required this.onClose,
    super.key,
  });
  final String error;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  @override
  State<PlaybackError> createState() => _PlaybackErrorState();
}

class _PlaybackErrorState extends State<PlaybackError> {
  final _retryFocus = FocusNode(debugLabel: 'Try again');

  @override
  void initState() {
    super.initState();
    // The player's root node already holds focus, so autofocus wouldn't
    // move it; take it explicitly or the D-pad has nothing to drive.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _retryFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _retryFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xE6000000),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Playback problem',
              style: SoupType.style(size: 30, weight: 800, letterSpacing: -1),
            ),
            const SizedBox(height: 10),
            Text(
              widget.error,
              key: const ValueKey('playback-error'),
              textAlign: TextAlign.center,
              style: SoupType.style(size: 16, color: SoupColors.muted),
            ),
            const SizedBox(height: 22),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SoupButton(
                  label: 'Try again',
                  onPressed: widget.onRetry,
                  focusNode: _retryFocus,
                ),
                const SizedBox(width: 12),
                SoupButton(
                  label: 'Back',
                  onPressed: widget.onClose,
                  style: SoupButtonStyle.glass,
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

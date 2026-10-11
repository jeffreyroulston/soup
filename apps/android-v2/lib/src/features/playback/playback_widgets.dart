import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:soup_core/soup_core.dart';

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
                : (focused ? const Color(0xBF48484E) : const Color(0x99282828)),
            border: filled ? null : Border.all(color: const Color(0x1AFFFFFF)),
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
class SeekBar extends StatelessWidget {
  const SeekBar({
    required this.position,
    required this.duration,
    required this.chapterFractions,
    required this.onSeekBy,
    this.focusNode,
    super.key,
  });

  final Duration position;
  final Duration duration;
  final List<double> chapterFractions;
  final void Function(Duration delta) onSeekBy;
  final FocusNode? focusNode;

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
          final focused = Focus.of(context).hasFocus;
          final height = focused ? 10.0 : 8.0;
          return SizedBox(
            key: const ValueKey('playback-seekbar'),
            height: 24,
            child: LayoutBuilder(
              builder: (context, c) => Stack(
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
          );
        },
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
            : (focused ? const Color(0xBF48484E) : const Color(0x99282828)),
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

class PlaybackError extends StatelessWidget {
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
              error,
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
                  onPressed: onRetry,
                  autofocus: true,
                ),
                const SizedBox(width: 12),
                SoupButton(
                  label: 'Back',
                  onPressed: onClose,
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

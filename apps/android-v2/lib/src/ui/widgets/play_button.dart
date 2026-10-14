import 'package:flutter/material.dart';

import '../theme/soup_tokens.dart';
import 'focusable.dart';

/// Web PlayButton: the white Play / Resume button. With progress, the time
/// left sits beside the label and a bar runs along the bottom edge.
class PlayButton extends StatelessWidget {
  const PlayButton({
    required this.label,
    required this.onActivate,
    this.detail,
    this.progress = 0,
    this.icon = true,
    this.autofocus = false,
    this.expand = false,
    this.height = 56,
    this.compact = false,
    super.key,
  });

  final String label;
  final VoidCallback? onActivate;

  /// e.g. "38 min left".
  final String? detail;

  /// 0–1; 0 hides the bar.
  final double progress;
  final bool icon;
  final bool autofocus;
  final bool expand;
  final double height;

  /// Touch sizing: smaller type and padding.
  final bool compact;

  @override
  Widget build(BuildContext context) => Focusable(
    autofocus: autofocus,
    radius: SoupRadii.button,
    onActivate: onActivate,
    builder: (context, _) => ClipRRect(
      borderRadius: BorderRadius.circular(SoupRadii.button),
      child: ColoredBox(
        color: SoupColors.ink,
        child: SizedBox(
          height: height,
          width: expand ? double.infinity : null,
          child: Stack(
            alignment: Alignment.center,
            fit: expand ? StackFit.expand : StackFit.loose,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: compact ? 20 : 26),
                child: Row(
                  mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon) ...[
                      Icon(
                        Icons.play_arrow_rounded,
                        color: SoupColors.canvas,
                        size: compact ? 22 : 26,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SoupType.style(
                          size: compact ? 16 : 18,
                          weight: 800,
                          color: SoupColors.canvas,
                        ),
                      ),
                    ),
                    if (detail != null) ...[
                      const SizedBox(width: 10),
                      Text(
                        detail!,
                        maxLines: 1,
                        style: SoupType.style(
                          size: compact ? 13 : 15,
                          weight: 700,
                          color: SoupColors.canvas.withValues(alpha: .7),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (progress > 0)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: LinearProgressIndicator(
                    value: progress.clamp(0, 1),
                    minHeight: 4,
                    color: SoupColors.accent,
                    backgroundColor: SoupColors.canvas.withValues(alpha: .15),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

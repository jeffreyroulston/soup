import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:soup_core/soup_core.dart';

import '../../data/models.dart';
import '../../ui/theme/soup_tokens.dart';
import '../../ui/widgets/catalog_image.dart';
import '../../ui/widgets/focusable.dart';

/// Labelled glass pill for the touch player's action row.
class PlayerPill extends StatelessWidget {
  const PlayerPill({
    required this.label,
    required this.onPressed,
    this.icon,
    this.trailingIcon,
    this.primary = false,
    super.key,
  });

  final String label;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool primary;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final fg = primary ? SoupColors.canvas : SoupColors.ink;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Focusable(
        onActivate: onPressed,
        radius: 20,
        builder: (context, focused) => Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: primary
                ? SoupColors.ink
                : (focused ? const Color(0xBF48484E) : const Color(0x99282828)),
            borderRadius: BorderRadius.circular(20),
            border: primary ? null : Border.all(color: const Color(0x1AFFFFFF)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: SoupType.style(size: 13, weight: 700, color: fg),
              ),
              if (trailingIcon != null) ...[
                const SizedBox(width: 8),
                Icon(trailingIcon, size: 16, color: fg),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Edge-to-edge seek bar for touch: a thin accent track that thickens while
/// dragging, with a time/chapter bubble riding above the thumb.
class TouchSeekBar extends StatelessWidget {
  const TouchSeekBar({
    required this.position,
    required this.duration,
    required this.chapterFractions,
    required this.onScrub,
    required this.onScrubEnd,
    this.scrubFrom,
    this.bubble,
    super.key,
  });

  final Duration position;
  final Duration duration;
  final List<double> chapterFractions;
  final ValueChanged<Duration> onScrub;
  final VoidCallback onScrubEnd;

  /// Where the current drag started; non-null while scrubbing.
  final Duration? scrubFrom;

  /// Shown above the thumb while scrubbing.
  final Widget? bubble;

  /// Width of the [bubble] slot.
  static const bubbleWidth = 180.0;

  double _fraction(Duration d) {
    final total = duration.inMilliseconds;
    return total <= 0 ? 0 : (d.inMilliseconds / total).clamp(0.0, 1.0);
  }

  Duration _at(double dx, double width) =>
      width <= 0 ? Duration.zero : duration * (dx / width).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final scrubbing = scrubFrom != null;
    final track = scrubbing ? 8.0 : 4.0;
    final thumb = scrubbing ? 22.0 : 14.0;
    final fraction = _fraction(position);
    return SizedBox(
      key: const ValueKey('playback-seekbar'),
      height: 32,
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => onScrub(_at(d.localPosition.dx, w)),
            onTapUp: (_) => onScrubEnd(),
            onHorizontalDragStart: (d) => onScrub(_at(d.localPosition.dx, w)),
            onHorizontalDragUpdate: (d) => onScrub(_at(d.localPosition.dx, w)),
            onHorizontalDragEnd: (_) => onScrubEnd(),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: track,
                  decoration: BoxDecoration(
                    color: const Color(0x38FFFFFF),
                    borderRadius: BorderRadius.circular(track / 2),
                  ),
                ),
                if (scrubbing)
                  Container(
                    height: track,
                    width: w * _fraction(scrubFrom!),
                    decoration: BoxDecoration(
                      color: const Color(0x73FC7814),
                      borderRadius: BorderRadius.circular(track / 2),
                    ),
                  ),
                Container(
                  height: track,
                  width: w * fraction,
                  decoration: BoxDecoration(
                    color: SoupColors.accent,
                    borderRadius: BorderRadius.circular(track / 2),
                  ),
                ),
                for (final f in chapterFractions)
                  Positioned(
                    left: w * f - 1,
                    child: Container(
                      width: 2,
                      height: track,
                      color: const Color(0xCC000000),
                    ),
                  ),
                if (scrubbing)
                  Positioned(
                    left: w * _fraction(scrubFrom!) - 1,
                    child: Container(
                      width: 2,
                      height: 20,
                      color: const Color(0x99F5F5F7),
                    ),
                  ),
                Positioned(
                  left: (w * fraction - thumb / 2).clamp(0.0, w - thumb),
                  child: Container(
                    width: thumb,
                    height: thumb,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: SoupColors.ink,
                      boxShadow: [
                        if (scrubbing)
                          const BoxShadow(
                            color: Color(0x4DFC7814),
                            spreadRadius: 6,
                          ),
                        const BoxShadow(
                          color: Color(0x80000000),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                ),
                if (scrubbing && bubble != null)
                  Positioned(
                    left: (w * fraction - bubbleWidth / 2).clamp(
                      0.0,
                      w - bubbleWidth,
                    ),
                    bottom: 30,
                    width: bubbleWidth,
                    child: IgnorePointer(child: bubble!),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Big time + chapter label (and a trickplay thumbnail, when the server has
/// them) shown above the thumb while scrubbing.
class ScrubBubble extends StatelessWidget {
  const ScrubBubble({
    required this.time,
    this.chapter,
    this.preview,
    super.key,
  });
  final String time;
  final String? chapter;

  /// Trickplay thumbnail shown above the time.
  final Widget? preview;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (preview != null) ...[preview!, const SizedBox(height: 8)],
      Text(
        time,
        key: const ValueKey('scrub-time'),
        style: SoupType.style(size: 22, weight: 800, letterSpacing: -0.4),
      ),
      if (chapter != null)
        Text(
          chapter!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: SoupType.style(size: 12, weight: 600, color: SoupColors.muted),
        ),
    ],
  );
}

/// Bottom sheet shell: grab handle, a header row with a close button, body.
class PlayerSheet extends StatelessWidget {
  const PlayerSheet({
    required this.header,
    required this.child,
    required this.onClose,
    this.padding = const EdgeInsets.fromLTRB(20, 0, 20, 0),
    super.key,
  });

  final Widget header;
  final Widget child;
  final VoidCallback onClose;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: Color(0xF01C1C1E),
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      border: Border(
        top: BorderSide(color: Color(0x14FFFFFF)),
        left: BorderSide(color: Color(0x14FFFFFF)),
        right: BorderSide(color: Color(0x14FFFFFF)),
      ),
    ),
    child: SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragEnd: (d) {
              if ((d.primaryVelocity ?? 0) > 200) onClose();
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 8, bottom: 10),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0x40FFFFFF),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(padding.left, 0, 20, 10),
                  child: Row(
                    children: [
                      Expanded(child: header),
                      _SheetClose(onClose: onClose),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: Padding(
              padding: EdgeInsets.only(
                left: padding.left,
                right: padding.right,
              ),
              child: child,
            ),
          ),
        ],
      ),
    ),
  );
}

class _SheetClose extends StatelessWidget {
  const _SheetClose({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Close',
    child: Focusable(
      onActivate: onClose,
      radius: 18,
      builder: (context, focused) => Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: focused ? const Color(0x33FFFFFF) : const Color(0x14FFFFFF),
        ),
        child: const Icon(PhosphorIconsRegular.x, size: 18),
      ),
    ),
  );
}

/// Settings sheet: a segmented control over the given tabs.
class SettingsSheet extends StatefulWidget {
  const SettingsSheet({required this.tabs, required this.onClose, super.key});

  final List<(String, Widget)> tabs;
  final VoidCallback onClose;

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final tab = _tab.clamp(0, widget.tabs.length - 1);
    return PlayerSheet(
      key: const ValueKey('panel-Settings'),
      onClose: widget.onClose,
      header: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: const Color(0x12FFFFFF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (i, t) in widget.tabs.indexed)
                Focusable(
                  key: ValueKey('settings-tab-${t.$1}'),
                  onActivate: () => setState(() => _tab = i),
                  scale: 1,
                  radius: 9,
                  builder: (context, focused) => Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == tab
                          ? SoupColors.ink
                          : (focused ? const Color(0x26FFFFFF) : null),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      t.$1,
                      style: SoupType.style(
                        size: 13,
                        weight: i == tab ? 800 : 700,
                        color: i == tab ? SoupColors.canvas : SoupColors.ink2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      child: widget.tabs[tab].$2,
    );
  }
}

/// Uppercase muted label above a group of options in a sheet.
class SheetLabel extends StatelessWidget {
  const SheetLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
    child: Text(
      text.toUpperCase(),
      style: SoupType.style(
        size: 11,
        weight: 800,
        color: SoupColors.muted,
        letterSpacing: 1,
      ),
    ),
  );
}

/// Horizontal strip of episode stills, scrolled to the current episode.
class EpisodesDrawer extends StatefulWidget {
  const EpisodesDrawer({
    required this.title,
    required this.episodes,
    required this.currentId,
    required this.onSelect,
    required this.onClose,
    super.key,
  });

  final String title;
  final List<CatalogItem> episodes;
  final String currentId;
  final ValueChanged<CatalogItem> onSelect;
  final VoidCallback onClose;

  @override
  State<EpisodesDrawer> createState() => _EpisodesDrawerState();
}

class _EpisodesDrawerState extends State<EpisodesDrawer> {
  static const _cardWidth = 200.0;
  static const _gap = 14.0;
  late final ScrollController _scroll;

  @override
  void initState() {
    super.initState();
    final index = widget.episodes.indexWhere((e) => e.id == widget.currentId);
    _scroll = ScrollController(
      initialScrollOffset: index <= 0 ? 0 : (index - 1) * (_cardWidth + _gap),
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PlayerSheet(
    key: const ValueKey('panel-Episodes'),
    onClose: widget.onClose,
    padding: const EdgeInsets.only(left: 20),
    header: Text(
      widget.title,
      style: SoupType.style(size: 16, weight: 800, letterSpacing: -0.3),
    ),
    child: SizedBox(
      height: 188,
      child: ListView.separated(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(right: 20, top: 4, bottom: 12),
        itemCount: widget.episodes.length,
        separatorBuilder: (_, _) => const SizedBox(width: _gap),
        itemBuilder: (context, i) {
          final e = widget.episodes[i];
          return _EpisodeCard(
            episode: e,
            current: e.id == widget.currentId,
            width: _cardWidth,
            onTap: () => widget.onSelect(e),
          );
        },
      ),
    ),
  );
}

class _EpisodeCard extends StatelessWidget {
  const _EpisodeCard({
    required this.episode,
    required this.current,
    required this.width,
    required this.onTap,
  });

  final CatalogItem episode;
  final bool current;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final e = episode;
    final runtime = e.runTimeTicks == null
        ? null
        : '${(e.runTimeTicks! / 600000000).round()}m';
    final progress = e.played
        ? 1.0
        : ((e.playedPercentage ?? 0) / 100).clamp(0.0, 1.0);
    return Focusable(
      onActivate: onTap,
      radius: 12,
      builder: (context, focused) => SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: current ? SoupColors.accent : Colors.transparent,
                  width: 2,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CatalogImage(
                        image: e.landscape,
                        maxWidth: 400,
                        fallbackTitle: e.name,
                        fallbackFontSize: 14,
                      ),
                      if (current)
                        Positioned(
                          left: 6,
                          top: 6,
                          child: _Badge(
                            color: SoupColors.accent,
                            child: Text(
                              'Now playing',
                              style: SoupType.style(
                                size: 11,
                                weight: 800,
                                color: SoupColors.canvas,
                              ),
                            ),
                          ),
                        )
                      else if (e.played)
                        const Positioned(
                          right: 6,
                          top: 6,
                          child: _Badge(
                            color: Color(0x99000000),
                            child: Icon(PhosphorIconsBold.check, size: 12),
                          ),
                        ),
                      if (runtime != null)
                        Positioned(
                          right: 6,
                          bottom: 7,
                          child: Text(
                            runtime,
                            style:
                                SoupType.style(
                                  size: 11,
                                  weight: 700,
                                  color: SoupColors.ink2,
                                ).copyWith(
                                  shadows: const [
                                    Shadow(
                                      color: Color(0xCC000000),
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                          ),
                        ),
                      if (progress > 0)
                        Align(
                          alignment: Alignment.bottomLeft,
                          child: FractionallySizedBox(
                            widthFactor: progress,
                            child: Container(
                              height: 3,
                              color: e.played
                                  ? const Color(0x8CF5F5F7)
                                  : SoupColors.accent,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              e.indexNumber == null ? '' : 'Episode ${e.indexNumber}',
              style: SoupType.style(
                size: 12,
                weight: 700,
                color: SoupColors.muted,
              ),
            ),
            Text(
              e.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SoupType.style(size: 14, weight: 800),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.color, required this.child});
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
    padding: const EdgeInsets.symmetric(horizontal: 6),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(11),
    ),
    child: child,
  );
}

/// Compact "Direct"/"Transcode" status for the touch top bar.
class MethodDot extends StatelessWidget {
  const MethodDot({required this.method, super.key});
  final JellyfinPlayMethod method;

  @override
  Widget build(BuildContext context) {
    final direct = method != JellyfinPlayMethod.transcode;
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0x99282828),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x1AFFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: direct ? SoupColors.ok : SoupColors.accent,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            direct ? 'Direct' : 'Transcode',
            key: const ValueKey('playback-method'),
            style: SoupType.style(size: 12, weight: 700),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ui/theme/soup_tokens.dart';
import '../../ui/widgets/focusable.dart';
import '../../ui/widgets/glass.dart';

class PanelOption {
  const PanelOption({
    required this.label,
    required this.onSelect,
    this.detail,
    this.selected = false,
    this.enabled = true,
  });
  final String label;
  final String? detail;
  final bool selected;
  final bool enabled;
  final VoidCallback onSelect;
}

class PanelSection {
  const PanelSection({
    required this.title,
    required this.options,
    this.chips = false,
    this.note,
  });
  final String title;
  final List<PanelOption> options;

  /// Lay options out as one horizontal row of equal chips (speed).
  final bool chips;
  final String? note;
}

/// Right-hand glass-strong panel (web: 440 wide, rounded 22). Back closes, as
/// does Left when nothing in the panel lies further left.
class SidePanel extends StatelessWidget {
  const SidePanel({
    required this.title,
    required this.sections,
    required this.onClose,
    this.header,
    this.footer,
    super.key,
  });

  final String title;
  final List<PanelSection> sections;
  final VoidCallback onClose;

  /// Pinned in the panel's top-left corner, above the title.
  final Widget? header;
  final String? footer;

  /// Room for the focus ring, which draws outside each row; the list clips
  /// at its bounds, so rows sit this far inside it.
  static const _ringRoom = 8.0;

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.sizeOf(context).width * 0.42).clamp(280.0, 440.0);
    // The first selected row (else the first enabled one) takes focus on open.
    final all = [for (final s in sections) ...s.options];
    final target =
        all.where((o) => o.selected && o.enabled).firstOrNull ??
        all.where((o) => o.enabled).firstOrNull;

    Widget sectionWidget(PanelSection s) {
      Widget row(PanelOption o) => s.chips
          ? PanelChip(option: o, autofocus: identical(o, target))
          : PanelRow(option: o, autofocus: identical(o, target));
      return Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(s.title),
            if (s.chips)
              Row(
                children: [
                  for (final (i, o) in s.options.indexed) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(child: row(o)),
                  ],
                ],
              )
            else
              for (final o in s.options) row(o),
            if (s.note != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  s.note!,
                  style: SoupType.style(size: 12, color: SoupColors.muted),
                ),
              ),
          ],
        ),
      );
    }

    return FocusScope(
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            // Left moves along a chip row; only at its start does it close.
            final moved =
                FocusManager.instance.primaryFocus?.focusInDirection(
                  TraversalDirection.left,
                ) ??
                false;
            if (!moved) onClose();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: SizedBox(
          key: ValueKey('panel-$title'),
          width: width,
          child: Glass(
            strong: true,
            padding: const EdgeInsets.fromLTRB(
              20 - _ringRoom,
              18,
              20 - _ringRoom,
              8,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (header != null)
                  Padding(
                    padding: const EdgeInsets.only(left: _ringRoom, bottom: 12),
                    child: header,
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _ringRoom),
                  child: Text(
                    title,
                    style: SoupType.style(
                      size: 22,
                      weight: 800,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 12 - _ringRoom),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      _ringRoom,
                      _ringRoom,
                      _ringRoom,
                      12,
                    ),
                    children: [for (final s in sections) sectionWidget(s)],
                  ),
                ),
                if (footer != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      _ringRoom,
                      0,
                      _ringRoom,
                      10,
                    ),
                    child: Text(
                      footer!,
                      style: SoupType.style(size: 12, color: SoupColors.muted),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6, top: 4),
    child: Text(
      text.toUpperCase(),
      style: SoupType.style(
        size: 12,
        weight: 800,
        color: SoupColors.muted,
        letterSpacing: 0.6,
      ),
    ),
  );
}

class PanelRow extends StatelessWidget {
  const PanelRow({required this.option, this.autofocus = false, super.key});
  final PanelOption option;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Focusable(
    autofocus: autofocus,
    onActivate: option.enabled ? option.onSelect : null,
    scale: 1.0,
    radius: 12,
    builder: (context, focused) => Opacity(
      opacity: option.enabled ? 1 : 0.4,
      child: Container(
        constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: focused ? const Color(0x26FFFFFF) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.label,
                    style: SoupType.style(size: 15, weight: 700),
                  ),
                  if (option.detail != null)
                    Text(
                      option.detail!,
                      style: SoupType.style(size: 12, color: SoupColors.muted),
                    ),
                ],
              ),
            ),
            if (option.selected)
              const Icon(Icons.check_rounded, size: 20, color: SoupColors.ink),
          ],
        ),
      ),
    ),
  );
}

class PanelChip extends StatelessWidget {
  const PanelChip({required this.option, this.autofocus = false, super.key});
  final PanelOption option;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Focusable(
    autofocus: autofocus,
    onActivate: option.onSelect,
    scale: 1.0,
    radius: 18,
    builder: (context, focused) => Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: option.selected
            ? SoupColors.ink
            : (focused ? const Color(0x33FFFFFF) : SoupColors.faint),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        option.label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.visible,
        style: SoupType.style(
          size: 14,
          weight: 700,
          color: option.selected ? SoupColors.canvas : SoupColors.ink,
        ),
      ),
    ),
  );
}

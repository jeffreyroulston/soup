import 'package:flutter/material.dart';

import '../../form_factor.dart';
import '../soup_focus_policy.dart';
import '../theme/soup_tokens.dart';
import 'focusable.dart';
import 'glass.dart';

class SelectOption<T> {
  const SelectOption(this.value, this.label, {this.detail});
  final T value;
  final String label;
  final String? detail;
}

/// Pill trigger + glass list dialog (web SelectMenu), fully D-pad drivable.
class SelectMenu<T> extends StatelessWidget {
  const SelectMenu({
    required this.options,
    required this.value,
    required this.onChanged,
    this.prefix,
    this.icon,
    this.surface = false,
    this.autofocus = false,
    super.key,
  });

  final List<SelectOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;
  final String? prefix;
  final IconData? icon;
  final bool surface;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final current =
        options.where((o) => o.value == value).firstOrNull ?? options.first;
    return Focusable(
      autofocus: autofocus,
      radius: 22,
      onActivate: () => _open(context),
      builder: (context, focused) => Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: surface
              ? (focused ? SoupColors.elevated : SoupColors.surface)
              : (focused ? const Color(0xBF48484E) : const Color(0x99282828)),
          borderRadius: BorderRadius.circular(23),
          border: Border.all(color: const Color(0x1AFFFFFF)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: SoupColors.ink),
              const SizedBox(width: 8),
            ],
            if (prefix != null)
              Text(
                '$prefix  ',
                style: SoupType.style(
                  size: 15,
                  weight: 600,
                  color: SoupColors.muted,
                ),
              ),
            Text(current.label, style: SoupType.style(size: 15, weight: 700)),
            const SizedBox(width: 8),
            const Icon(
              Icons.expand_more_rounded,
              size: 20,
              color: SoupColors.ink2,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    if (context.isTouch) return _openSheet(context);
    final picked = await showDialog<_Picked<T>>(
      context: context,
      barrierColor: const Color(0x99000000),
      builder: (context) => Center(
        child: SizedBox(
          width: 420,
          child: Glass(
            strong: true,
            radius: SoupRadii.menu,
            padding: const EdgeInsets.all(8),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.7,
              ),
              child: FocusTraversalGroup(
                policy: SoupFocusPolicy(),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final o in options)
                      // Rows sit flush, so the focused one inverts rather
                      // than ringing over its neighbours.
                      Focusable(
                        autofocus: o.value == value,
                        scale: 1.0,
                        ring: false,
                        radius: 12,
                        onActivate: () =>
                            Navigator.of(context).pop(_Picked(o.value)),
                        builder: (context, focused) => Container(
                          constraints: const BoxConstraints(minHeight: 48),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: focused
                                ? SoupColors.ink
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 26,
                                child: o.value == value
                                    ? Icon(
                                        Icons.check_rounded,
                                        size: 20,
                                        color: focused
                                            ? SoupColors.canvas
                                            : SoupColors.ink,
                                      )
                                    : null,
                              ),
                              Expanded(
                                child: Text(
                                  o.label,
                                  style: SoupType.style(
                                    size: 17,
                                    weight: 600,
                                    color: focused
                                        ? SoupColors.canvas
                                        : SoupColors.ink,
                                  ),
                                ),
                              ),
                              if (o.detail != null)
                                Text(
                                  o.detail!,
                                  style: SoupType.style(
                                    size: 14,
                                    color: focused
                                        ? SoupColors.canvas.withValues(
                                            alpha: .6,
                                          )
                                        : SoupColors.muted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (picked != null) onChanged(picked.value);
  }
}

extension<T> on SelectMenu<T> {
  /// Touch: a bottom sheet of options instead of the centred TV dialog.
  Future<void> _openSheet(BuildContext context) async {
    final picked = await showModalBottomSheet<_Picked<T>>(
      context: context,
      backgroundColor: const Color(0xF21E1E20),
      showDragHandle: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.75,
      ),
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          children: [
            if (prefix != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  prefix!.toUpperCase(),
                  style: SoupType.style(
                    size: 12,
                    weight: 800,
                    color: SoupColors.muted,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            for (final o in options)
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: SizedBox(
                  width: 24,
                  child: o.value == value
                      ? const Icon(Icons.check_rounded, color: SoupColors.ink)
                      : null,
                ),
                title: Text(
                  o.label,
                  style: SoupType.style(size: 16, weight: 600),
                ),
                trailing: o.detail == null
                    ? null
                    : Text(
                        o.detail!,
                        style: SoupType.style(
                          size: 14,
                          color: SoupColors.muted,
                        ),
                      ),
                onTap: () => Navigator.of(sheet).pop(_Picked(o.value)),
              ),
          ],
        ),
      ),
    );
    if (picked != null) onChanged(picked.value);
  }
}

class _Picked<T> {
  const _Picked(this.value);
  final T value;
}

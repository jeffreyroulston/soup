import 'package:flutter/material.dart';

import '../theme/soup_tokens.dart';
import 'focusable.dart';

/// Web pill switcher (library filters, season tabs, shelf tabs, search scope).
class PillTabs<T> extends StatelessWidget {
  const PillTabs({
    required this.options,
    required this.value,
    required this.onChanged,
    this.labelOf,
    this.height = 40,
    super.key,
  });

  final List<T> options;
  final T value;
  final ValueChanged<T> onChanged;
  final String Function(T)? labelOf;
  final double height;

  String _text(T o) => labelOf != null ? labelOf!(o) : '$o';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: SoupColors.surface,
        borderRadius: BorderRadius.circular(height),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final o in options)
            Focusable(
              scale: 1.0,
              radius: height,
              onActivate: () => onChanged(o),
              builder: (context, focused) => Container(
                height: height - 6,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: o == value
                      ? SoupColors.ink
                      : (focused ? SoupColors.elevated : Colors.transparent),
                  borderRadius: BorderRadius.circular(height),
                ),
                child: Text(
                  _text(o),
                  style: SoupType.style(
                    size: 15,
                    weight: 700,
                    color: o == value ? SoupColors.canvas : SoupColors.ink2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../theme/soup_tokens.dart';

/// Year, runtime, genres… spaced apart rather than dot-separated (web
/// `gap-x-[18px]`), followed by rating/quality chips.
class MetaLine extends StatelessWidget {
  const MetaLine({
    required this.bits,
    this.chips = const [],
    this.size = 15,
    this.color = SoupColors.ink2,
    this.spacing = 18,
    this.alignment = WrapAlignment.start,
    super.key,
  });

  final List<String> bits;
  final List<String> chips;
  final double size;
  final Color color;
  final double spacing;
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: spacing,
    runSpacing: 8,
    alignment: alignment,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      for (final b in bits)
        Text(
          b,
          style: SoupType.style(size: size, weight: 600, color: color),
        ),
      for (final c in chips)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0x33FFFFFF),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(c, style: SoupType.style(size: size - 3, weight: 800)),
        ),
    ],
  );
}

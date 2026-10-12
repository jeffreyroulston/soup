import 'package:flutter/material.dart';

/// The fill-line app icon tile (docs/branding/soup-icon-rounded.svg), untinted.
class SoupMark extends StatelessWidget {
  const SoupMark({this.size = 40, super.key});

  static const assetName = 'assets/branding/soup-icon.png';
  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    assetName,
    width: size,
    height: size,
    filterQuality: FilterQuality.medium,
    excludeFromSemantics: true,
  );
}

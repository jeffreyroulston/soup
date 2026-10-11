import 'package:flutter/painting.dart';

/// Design tokens ported from apps/web/app/assets/css/main.css.
abstract final class SoupColors {
  static const canvas = Color(0xFF0A0A0B);
  static const surface = Color(0xFF1C1C1E);
  static const elevated = Color(0xFF2C2C2E);
  static const ink = Color(0xFFF5F5F7);
  static const ink2 = Color(0xFFD2D2D7);
  static const muted = Color(0xFFA1A1A6);
  static const accent = Color(0xFFFC7814);
  static const ok = Color(0xFF30D158);
}

abstract final class SoupRadii {
  static const card = 14.0;
  static const button = 12.0;
  static const panel = 22.0;
  static const menu = 18.0;
  static const spotlight = 28.0;
}

/// Gutters scaled up from the web's px-4/8/12 for a 10-foot UI.
abstract final class SoupSpacing {
  static const gutter = 56.0;
  static const rowGap = 40.0;
}

abstract final class SoupType {
  static const family = 'Manrope';

  /// Manrope ships as one variable font; weight is driven by the `wght` axis.
  static TextStyle style({
    required double size,
    int weight = 500,
    Color color = SoupColors.ink,
    double? letterSpacing,
    double? height,
  }) => TextStyle(
    fontFamily: family,
    fontSize: size,
    fontWeight: _bucket(weight),
    fontVariations: [FontVariation('wght', weight.toDouble())],
    color: color,
    letterSpacing: letterSpacing,
    height: height,
  );

  static FontWeight _bucket(int w) =>
      FontWeight.values[(w ~/ 100 - 1).clamp(0, 8)];
}

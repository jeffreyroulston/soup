import 'package:flutter/material.dart';

import 'soup_tokens.dart';

abstract final class SoupTheme {
  static ThemeData get dark {
    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      fontFamily: SoupType.family,
      scaffoldBackgroundColor: SoupColors.canvas,
      colorScheme: const ColorScheme.dark(
        primary: SoupColors.accent,
        onPrimary: SoupColors.canvas,
        surface: SoupColors.surface,
        onSurface: SoupColors.ink,
        surfaceContainerHighest: SoupColors.elevated,
        error: Color(0xFFFF6B5E),
      ),
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(
        fontFamily: SoupType.family,
        bodyColor: SoupColors.ink,
        displayColor: SoupColors.ink,
      ),
      // D-pad focus is drawn by Focusable; suppress Material's highlight.
      focusColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
    );
  }
}

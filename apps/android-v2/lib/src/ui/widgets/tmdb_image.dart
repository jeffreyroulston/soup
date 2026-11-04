import 'package:flutter/material.dart';

import '../../data/seerr_models.dart';
import '../theme/soup_tokens.dart';

/// TMDB artwork for Explore (posters, backdrops, headshots), fetched straight
/// from image.tmdb.org; the mock catalogue's bundled posters load as assets.
/// Falls back to the title-on-surface tile [CatalogImage] uses.
class TmdbImage extends StatelessWidget {
  const TmdbImage({
    required this.path,
    required this.kind,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.fallbackTitle,
    this.fallbackFontSize = 22,
    this.cacheWidth,
    super.key,
  });

  final String? path;
  final TmdbImageKind kind;
  final BoxFit fit;
  final Alignment alignment;
  final String? fallbackTitle;
  final double fallbackFontSize;

  /// Decode no larger than this; defaults per [kind].
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) {
    final url = tmdbImageUrl(path, kind);
    final fallback = _Fallback(
      title: fallbackTitle,
      fontSize: fallbackFontSize,
    );
    if (url == null) return fallback;
    final width =
        cacheWidth ??
        switch (kind) {
          TmdbImageKind.poster => 500,
          TmdbImageKind.backdrop => 1280,
          TmdbImageKind.profile => 185,
        };
    Widget error(BuildContext _, Object _, StackTrace? _) => fallback;
    if (url.startsWith('assets/')) {
      return Image.asset(
        url,
        fit: fit,
        alignment: alignment,
        width: double.infinity,
        height: double.infinity,
        cacheWidth: width,
        errorBuilder: error,
      );
    }
    return Image.network(
      url,
      fit: fit,
      alignment: alignment,
      width: double.infinity,
      height: double.infinity,
      cacheWidth: width,
      gaplessPlayback: true,
      errorBuilder: error,
      frameBuilder: (context, child, frame, synchronouslyLoaded) {
        if (synchronouslyLoaded || frame != null) return child;
        return _Fallback(title: null, fontSize: fallbackFontSize);
      },
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.title, required this.fontSize});
  final String? title;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    height: double.infinity,
    color: SoupColors.surface,
    alignment: Alignment.bottomLeft,
    padding: const EdgeInsets.all(14),
    child: title == null
        ? null
        : Text(
            title!,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: SoupType.style(
              size: fontSize,
              weight: 800,
              letterSpacing: -0.5,
              height: 1.05,
            ),
          ),
  );
}

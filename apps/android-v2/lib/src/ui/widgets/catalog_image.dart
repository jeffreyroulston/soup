import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../data/models.dart';
import '../theme/soup_tokens.dart';

/// Artwork loaded through the catalog (so it rides the Tailscale transport).
/// Falls back to the web's title-on-gradient tile when there is no image.
class CatalogImage extends StatefulWidget {
  const CatalogImage({
    required this.image,
    this.maxWidth = 480,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.fallbackTitle,
    this.fallbackFontSize = 22,
    super.key,
  });

  final ImageRef image;
  final int maxWidth;
  final BoxFit fit;
  final Alignment alignment;

  /// Shown on a tinted gradient when the image is missing or still loading.
  final String? fallbackTitle;
  final double fallbackFontSize;

  @override
  State<CatalogImage> createState() => _CatalogImageState();
}

class _CatalogImageState extends State<CatalogImage> {
  Future<Uint8List?>? _future;
  ImageRef? _loaded;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(CatalogImage old) {
    super.didUpdateWidget(old);
    _load();
  }

  void _load() {
    if (_loaded == widget.image && _future != null) return;
    _loaded = widget.image;
    _future = SoupScope.of(
      context,
    ).catalog.image(widget.image, maxWidth: widget.maxWidth);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: bytes != null
              ? Image.memory(
                  bytes,
                  key: ValueKey(widget.image),
                  fit: widget.fit,
                  alignment: widget.alignment,
                  gaplessPlayback: true,
                  width: double.infinity,
                  height: double.infinity,
                  // Never decode past the requested size, whatever the server
                  // sends (it can't upscale, so small images stay as they are).
                  cacheWidth: widget.maxWidth,
                  // Corrupt or unsupported bytes get the title tile, not
                  // Flutter's broken-image box.
                  errorBuilder: (_, _, _) => _Fallback(
                    title: widget.fallbackTitle,
                    fontSize: widget.fallbackFontSize,
                  ),
                )
              : _Fallback(
                  key: const ValueKey('fallback'),
                  title: snapshot.connectionState == ConnectionState.done
                      ? widget.fallbackTitle
                      : null,
                  fontSize: widget.fallbackFontSize,
                ),
        );
      },
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.title, required this.fontSize, super.key});
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

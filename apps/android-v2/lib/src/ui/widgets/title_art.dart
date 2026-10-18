import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../data/models.dart';

/// Title art (the item's transparent logo) in place of the text title, as on
/// the web hero and item page. [fallback] shows when there is no logo or it
/// fails to load.
class TitleArt extends StatefulWidget {
  const TitleArt({
    required this.logo,
    required this.fallback,
    required this.maxWidth,
    required this.maxHeight,
    this.alignment = Alignment.centerLeft,
    super.key,
  });

  final ImageRef? logo;
  final Widget fallback;
  final double maxWidth;
  final double maxHeight;
  final Alignment alignment;

  @override
  State<TitleArt> createState() => _TitleArtState();
}

class _TitleArtState extends State<TitleArt> {
  Future<Uint8List?>? _future;
  ImageRef? _loaded;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(TitleArt old) {
    super.didUpdateWidget(old);
    _load();
  }

  static const _logoWidth = 800;

  void _load() {
    final logo = widget.logo;
    if (logo == _loaded && (_future != null || logo == null)) return;
    _loaded = logo;
    _future = logo == null
        ? null
        : SoupScope.of(context).catalog.image(logo, maxWidth: _logoWidth);
  }

  @override
  Widget build(BuildContext context) {
    if (_future == null) return widget.fallback;
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snapshot) {
        // Hold the logo's space while it loads so the copy below doesn't jump.
        if (snapshot.connectionState != ConnectionState.done) {
          return SizedBox(height: widget.maxHeight * 0.6);
        }
        final bytes = snapshot.data;
        if (bytes == null) return widget.fallback;
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: widget.maxWidth,
            maxHeight: widget.maxHeight,
          ),
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            alignment: widget.alignment,
            gaplessPlayback: true,
            cacheWidth: _logoWidth,
            errorBuilder: (_, _, _) => widget.fallback,
          ),
        );
      },
    );
  }
}

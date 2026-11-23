import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../data/catalog.dart';
import '../theme/soup_tokens.dart';

/// Circular user avatar loaded from Jellyfin through the catalog, falling
/// back to the user's initial (or [fallback]) when no profile picture is set.
class UserAvatar extends StatefulWidget {
  const UserAvatar({
    required this.label,
    this.size = 44,
    this.fontSize,
    this.backgroundColor = SoupColors.accent,
    this.foregroundColor = SoupColors.canvas,
    this.border,
    this.fallback,
    super.key,
  });

  final String label;
  final double size;
  final double? fontSize;
  final Color backgroundColor;
  final Color foregroundColor;
  final BoxBorder? border;

  /// Shown instead of the circular initial tile when no picture is available
  /// (e.g. a Material icon in the touch bottom nav).
  final Widget? fallback;

  /// Last avatar bytes seen per catalog, so a new page's nav draws the picture
  /// on its first frame instead of flashing the initial while the cache resolves.
  static final _cached = Expando<Uint8List>();

  @override
  State<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends State<UserAvatar> {
  Catalog? _catalog;
  int _revision = -1;
  Future<Uint8List?>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final catalog = SoupScope.maybeOf(context)?.catalog;
    if (!identical(catalog, _catalog)) {
      _catalog?.removeListener(_onCatalogChanged);
      _catalog = catalog;
      _catalog?.addListener(_onCatalogChanged);
      _load();
    }
  }

  @override
  void dispose() {
    _catalog?.removeListener(_onCatalogChanged);
    super.dispose();
  }

  void _onCatalogChanged() {
    if (!mounted || _catalog == null) return;
    if (_catalog!.revision != _revision) {
      setState(_load);
    }
  }

  void _load() {
    final catalog = _catalog;
    if (catalog == null) {
      _revision = -1;
      _future = null;
      return;
    }
    _revision = catalog.revision;
    final future = catalog.userAvatar();
    _future = future;
    unawaited(
      future.then<void>((bytes) {
        if (identical(_catalog, catalog)) {
          UserAvatar._cached[catalog] = bytes;
        }
      }, onError: (Object _) {}),
    );
  }

  Widget _initial() => Container(
    width: widget.size,
    height: widget.size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: widget.backgroundColor,
      shape: BoxShape.circle,
      border: widget.border,
    ),
    child: Text(
      widget.label.isEmpty ? '·' : widget.label[0].toUpperCase(),
      style: SoupType.style(
        size: widget.fontSize ?? widget.size * 0.41,
        weight: 800,
        color: widget.foregroundColor,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final catalog = _catalog;
    final initialData = catalog == null ? null : UserAvatar._cached[catalog];
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = (widget.size * dpr).round().clamp(48, 512);
    return FutureBuilder<Uint8List?>(
      future: _future,
      initialData: initialData,
      builder: (context, snapshot) {
        final bytes = snapshot.connectionState == ConnectionState.done
            ? snapshot.data
            : (snapshot.data ?? initialData);
        final fallback = widget.fallback ?? _initial();
        if (bytes == null || bytes.isEmpty) return fallback;
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: widget.fallback == null ? widget.backgroundColor : null,
            shape: BoxShape.circle,
          ),
          foregroundDecoration: widget.border == null
              ? null
              : BoxDecoration(shape: BoxShape.circle, border: widget.border),
          clipBehavior: Clip.antiAlias,
          child: Image.memory(
            bytes,
            width: widget.size,
            height: widget.size,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            cacheWidth: cacheWidth,
            errorBuilder: (_, _, _) => fallback,
          ),
        );
      },
    );
  }
}

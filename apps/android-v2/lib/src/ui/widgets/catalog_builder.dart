import 'package:flutter/widgets.dart';

import '../../app_scope.dart';
import '../../data/catalog.dart';
import '../../data/connection_status.dart';

/// Loads data from the [Catalog] and reloads when the catalog invalidates
/// (favourite/watched toggles). Keeps showing stale data while reloading.
class CatalogBuilder<T> extends StatefulWidget {
  const CatalogBuilder({
    required this.load,
    required this.builder,
    this.keys = const [],
    super.key,
  });

  final Future<T> Function(Catalog catalog) load;

  /// `data` is null until the first load completes; `error` is set on failure.
  final Widget Function(BuildContext context, T? data, Object? error) builder;

  /// Reload when any of these change.
  final List<Object?> keys;

  @override
  State<CatalogBuilder<T>> createState() => _CatalogBuilderState<T>();
}

class _CatalogBuilderState<T> extends State<CatalogBuilder<T>> {
  Catalog? _catalog;
  ConnectionStatus? _connection;
  T? _data;
  Object? _error;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = SoupScope.of(context);
    _connection = scope.connection;
    final catalog = scope.catalog;
    if (!identical(catalog, _catalog)) {
      _catalog?.removeListener(_reload);
      _catalog = catalog..addListener(_reload);
      _reload();
    }
  }

  @override
  void didUpdateWidget(CatalogBuilder<T> old) {
    super.didUpdateWidget(old);
    if (!_sameKeys(old.keys, widget.keys)) {
      _data = null;
      _reload();
    }
  }

  bool _sameKeys(List<Object?> a, List<Object?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _reload() {
    final generation = ++_generation;
    widget
        .load(_catalog!)
        .then(
          (value) {
            if (!mounted || generation != _generation) return;
            _connection?.reportOk();
            setState(() {
              _data = value;
              _error = null;
            });
          },
          onError: (Object error) {
            if (!mounted || generation != _generation) return;
            _connection?.report(error);
            setState(() => _error = error);
          },
        );
  }

  @override
  void dispose() {
    _catalog?.removeListener(_reload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _data, _error);
}

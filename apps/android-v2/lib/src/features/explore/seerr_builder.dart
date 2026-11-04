import 'package:flutter/widgets.dart';

import '../../data/seerr.dart';

/// Loads data from [Seerr] and reloads when it invalidates (a request made
/// or withdrawn), keeping stale data on screen while it does. Pages that
/// aren't showing reload when they're uncovered.
///
/// Seerr failures stay here: they're never reported to the shared
/// [ConnectionStatus], so a down Seerr doesn't read as a down Jellyfin.
class SeerrBuilder<T> extends StatefulWidget {
  const SeerrBuilder({
    required this.load,
    required this.builder,
    this.keys = const [],
    super.key,
  });

  final Future<T> Function(Seerr seerr) load;

  /// `data` is null until the first load completes; `error` is set on failure.
  final Widget Function(BuildContext context, T? data, Object? error) builder;

  /// Reload when any of these change.
  final List<Object?> keys;

  @override
  State<SeerrBuilder<T>> createState() => _SeerrBuilderState<T>();
}

class _SeerrBuilderState<T> extends State<SeerrBuilder<T>> {
  Seerr? _seerr;
  T? _data;
  Object? _error;
  int _generation = 0;
  bool _stale = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = _visible;
    final seerr = Seerr.of(context);
    if (!identical(seerr, _seerr)) {
      _seerr?.removeListener(_invalidated);
      _seerr = seerr..addListener(_invalidated);
      _reload();
    } else if (_stale && visible) {
      _reload();
    }
  }

  bool get _visible => ModalRoute.of(context)?.isCurrent ?? true;

  void _invalidated() {
    if (_visible) {
      _reload();
    } else {
      _stale = true;
    }
  }

  @override
  void didUpdateWidget(SeerrBuilder<T> old) {
    super.didUpdateWidget(old);
    if (!_sameKeys(old.keys, widget.keys)) {
      _data = null;
      _error = null;
      _reload();
    }
  }

  static bool _sameKeys(List<Object?> a, List<Object?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _reload() {
    _stale = false;
    final generation = ++_generation;
    widget
        .load(_seerr!)
        .then(
          (value) {
            if (!mounted || generation != _generation) return;
            setState(() {
              _data = value;
              _error = null;
            });
          },
          onError: (Object error) {
            if (!mounted || generation != _generation) return;
            setState(() => _error = error);
          },
        );
  }

  @override
  void dispose() {
    _seerr?.removeListener(_invalidated);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _data, _error);
}

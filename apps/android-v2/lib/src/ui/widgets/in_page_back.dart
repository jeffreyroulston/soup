import 'package:flutter/widgets.dart';

/// In-page states that Back should close before the page's own Back runs
/// (the poster wall's reveal). Only top-level pages consult it: their shells
/// never let Back pop the route outright, so they always get to ask first.
abstract final class InPageBack {
  static final _entries =
      <({ModalRoute<Object?>? route, VoidCallback close})>[];

  /// Back on [route] calls [close] (once) until it's [remove]d.
  static void add(ModalRoute<Object?>? route, VoidCallback close) =>
      _entries.add((route: route, close: close));

  static void remove(VoidCallback close) =>
      _entries.removeWhere((e) => e.close == close);

  /// Closes the newest state on [route]; false when there's none.
  static bool handle(ModalRoute<Object?>? route) {
    for (var i = _entries.length - 1; i >= 0; i--) {
      final entry = _entries[i];
      if (entry.route != route) continue;
      _entries.removeAt(i);
      entry.close();
      return true;
    }
    return false;
  }
}

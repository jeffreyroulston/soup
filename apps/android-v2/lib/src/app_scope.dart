import 'package:flutter/widgets.dart';
import 'package:soup_core/soup_core.dart';

import 'data/catalog.dart';
import 'data/playback_prefs.dart';

/// Per-account dependencies for everything below the auth gate.
///
/// [api] and [session] are null in mock mode (`SOUP_MOCK=true`); playback then
/// falls back to a public sample stream.
class SoupScope extends InheritedWidget {
  const SoupScope({
    required this.catalog,
    required this.prefs,
    required this.onSignOut,
    required super.child,
    this.api,
    this.session,
    this.userLabel = '',
    super.key,
  });

  final Catalog catalog;
  final PlaybackPrefs prefs;
  final JellyfinApi? api;
  final JellyfinSession? session;
  final String userLabel;
  final Future<void> Function() onSignOut;

  bool get isMock => api == null;

  /// A copy of this scope around [child], for routes pushed on a navigator
  /// that sits above the scope.
  Widget rewrap(Widget child) => SoupScope(
    catalog: catalog,
    prefs: prefs,
    api: api,
    session: session,
    userLabel: userLabel,
    onSignOut: onSignOut,
    child: child,
  );

  static SoupScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SoupScope>();
    assert(scope != null, 'No SoupScope above this context');
    return scope!;
  }

  @override
  bool updateShouldNotify(SoupScope old) =>
      catalog != old.catalog || session != old.session || api != old.api;
}

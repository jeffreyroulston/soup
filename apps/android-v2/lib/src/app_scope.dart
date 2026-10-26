import 'package:flutter/widgets.dart';
import 'package:soup_core/soup_core.dart';

import 'data/catalog.dart';
import 'data/connection_status.dart';
import 'data/device_settings.dart';
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
    this.soupAuth,
    this.onSelectServer,
    this.connection,
    this.device,
    super.key,
  });

  final Catalog catalog;
  final PlaybackPrefs prefs;
  final JellyfinApi? api;
  final JellyfinSession? session;
  final String userLabel;
  final Future<void> Function() onSignOut;

  /// Soup sign-in, for the roster and the current server; null for direct
  /// Jellyfin sign-ins and mock mode.
  final SoupDeviceLinkViewModel? soupAuth;

  /// Switches to another roster server; returns an error message on failure.
  final Future<String?> Function(String serverId)? onSelectServer;

  /// Whether the server is answering; null in mock mode and tests.
  final ConnectionStatus? connection;

  /// This device's name, capabilities and audio setting; null in tests, where
  /// playback uses a conservative Android profile.
  final DeviceSettings? device;

  JellyfinDeviceProfile get deviceProfile =>
      device?.profile() ??
      JellyfinDeviceProfile(capabilities: DeviceCapabilities.fallback);

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
    soupAuth: soupAuth,
    onSelectServer: onSelectServer,
    connection: connection,
    device: device,
    child: child,
  );

  /// Null outside a signed-in session (sign-in screens, some tests).
  static SoupScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SoupScope>();

  static SoupScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SoupScope>();
    assert(scope != null, 'No SoupScope above this context');
    return scope!;
  }

  @override
  bool updateShouldNotify(SoupScope old) =>
      catalog != old.catalog ||
      session != old.session ||
      api != old.api ||
      connection != old.connection ||
      device != old.device;
}

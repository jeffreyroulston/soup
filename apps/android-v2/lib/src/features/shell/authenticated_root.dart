import 'dart:async';

import 'package:flutter/material.dart';
import 'package:soup_core/soup_core.dart';

import '../../app_scope.dart';
import '../../data/jellyfin_catalog.dart';
import '../../data/playback_prefs.dart';
import '../../ui/theme/soup_tokens.dart';
import '../home/home_screen.dart';
import '../shared/status_screen.dart';

/// Builds the live catalog for a signed-in session, validating a Soup-issued
/// Jellyfin token first (as v1's `_AuthenticatedHome` does).
class AuthenticatedRoot extends StatefulWidget {
  const AuthenticatedRoot({
    required this.connectivity,
    required this.session,
    required this.onSignOut,
    this.soupAuth,
    super.key,
  });

  final ConnectivityViewModel connectivity;
  final SoupDeviceLinkViewModel? soupAuth;
  final JellyfinSession session;
  final Future<void> Function() onSignOut;

  @override
  State<AuthenticatedRoot> createState() => _AuthenticatedRootState();
}

class _Ready {
  const _Ready(this.api, this.session, this.catalog);
  final JellyfinApi api;
  final JellyfinSession session;
  final JellyfinCatalog catalog;
}

class _AuthenticatedRootState extends State<AuthenticatedRoot> {
  late Future<_Ready> _ready = _load();
  JellyfinCatalog? _catalog;
  final _prefs = PlaybackPrefs()..load();

  Future<_Ready> _load() async {
    var session = widget.session;
    final soup = widget.soupAuth;
    if (soup != null && soup.performJellyfinExchange) {
      final ok = await soup.ensureJellyfinSessionValid();
      if (!ok) {
        throw const JellyfinApiException(
          'Your Soup sign-in expired. Sign in with Google again.',
          statusCode: 401,
        );
      }
      final fresh = soup.jellyfinSession;
      if (fresh != null && !identical(fresh, widget.connectivity.session)) {
        await widget.connectivity.adoptSoupJellyfinSession(fresh);
        session = fresh;
      } else if (fresh != null) {
        session = fresh;
      }
    }
    final api = await widget.connectivity.authenticatedApi();
    final catalog = JellyfinCatalog(api, session);
    _catalog = catalog;
    return _Ready(api, session, catalog);
  }

  /// The app rebuilds its navigator once the new Jellyfin session is adopted,
  /// so a successful switch reopens Home on that server.
  Future<String?> _selectServer(String serverId) async {
    final soup = widget.soupAuth!;
    if (serverId == soup.selectedServer?.id) return null;
    final error = await soup.selectServer(serverId);
    if (error != null) return error;
    final session = soup.jellyfinSession;
    if (session != null) {
      await widget.connectivity.adoptSoupJellyfinSession(session);
    }
    return null;
  }

  @override
  void dispose() {
    _catalog?.dispose();
    _prefs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Ready>(
      future: _ready,
      builder: (context, snapshot) {
        final ready = snapshot.data;
        if (ready != null) {
          return SoupScope(
            catalog: ready.catalog,
            prefs: _prefs,
            api: ready.api,
            session: ready.session,
            userLabel: ready.session.userName,
            onSignOut: widget.onSignOut,
            soupAuth: widget.soupAuth,
            onSelectServer: widget.soupAuth == null ? null : _selectServer,
            child: const HomeScreen(),
          );
        }
        if (snapshot.hasError) {
          final error = snapshot.error;
          final expired =
              error is JellyfinApiException && error.statusCode == 401;
          return StatusScreen(
            title: expired ? 'Sign-in needed' : 'Could not open your library',
            message: expired
                ? 'Your session expired. Sign in again.'
                : '${error is JellyfinApiException ? '${error.message} ' : ''}'
                      'If this keeps happening, sign out and sign in again.',
            secondaryLabel: expired ? null : 'Sign out',
            onSecondary: expired ? null : () => unawaited(widget.onSignOut()),
            onRetry: () {
              if (expired) {
                unawaited(widget.onSignOut());
                return;
              }
              setState(() => _ready = _load());
            },
          );
        }
        return const Scaffold(
          body: Center(
            child: CircularProgressIndicator(color: SoupColors.accent),
          ),
        );
      },
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:soup_core/soup_core.dart';

import '../../app_scope.dart';
import '../../data/connection_status.dart';
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

  /// Whether the server is answering. Learns its name up front, probes it
  /// with backoff while it's down, and reloads everything when it's back.
  late final _connection = ConnectionStatus(
    serverName: widget.soupAuth?.selectedServer?.name,
    probe: () async {
      final api = await widget.connectivity.authenticatedApi();
      final info = await api.getPublicSystemInfo(
        (widget.connectivity.session ?? widget.session).serverUrl,
      );
      return info.name;
    },
    onRecovered: () {
      final catalog = _catalog;
      if (catalog != null) {
        catalog.refresh();
      } else if (mounted) {
        setState(() => _ready = _load());
      }
    },
  )..start();

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
    // Fail fast (and friendly) when the server is down, instead of opening
    // onto screens that each fail on their own.
    try {
      await api.getPublicSystemInfo(session.serverUrl);
      _connection.reportOk();
    } on Object catch (error) {
      _connection.report(error);
      rethrow;
    }
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
    _connection.dispose();
    _prefs.dispose();
    super.dispose();
  }

  Widget _startupError(Object error) {
    var problem = ConnectionProblem.of(error);
    if (problem.retries && _connection.problem != null) {
      problem = _connection.problem!;
    }
    final copy = problemCopy(problem, _connection.serverName);
    if (problem == ConnectionProblem.signedOut) {
      return StatusScreen(
        title: copy.title,
        message: copy.message,
        onRetry: () => unawaited(widget.onSignOut()),
      );
    }
    final waiting = problem.retries && _connection.isDown;
    return StatusScreen(
      title: copy.title,
      message: waiting
          ? '${copy.message}\n\n${_connection.isRetrying ? 'Reconnecting…' : 'Retrying in ${_connection.secondsUntilRetry}s'}'
          : copy.message,
      busy: _connection.isRetrying,
      secondaryLabel: 'Sign out',
      onSecondary: () => unawaited(widget.onSignOut()),
      onRetry: _connection.isRetrying
          ? null
          : waiting
          ? () => unawaited(_connection.retryNow())
          : () => setState(() => _ready = _load()),
    );
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
            connection: _connection,
            child: const HomeScreen(),
          );
        }
        if (snapshot.hasError) {
          return ListenableBuilder(
            listenable: _connection,
            builder: (context, _) => _startupError(snapshot.error!),
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

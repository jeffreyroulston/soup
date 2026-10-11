import 'dart:async';

import 'package:flutter/material.dart';
import 'package:soup_core/soup_core.dart';
import 'package:soup_identity/soup_identity.dart';
import 'package:soup_tailscale/soup_tailscale.dart';

import 'features/auth/login_screen.dart';
import 'features/home/home_screen.dart';
import 'features/shared/status_screen.dart';
import 'ui/theme/soup_theme.dart';

/// Auth gate shared in shape with the v1 app: loading → Soup device-link →
/// Tailscale reconnect → authenticated. Direct Jellyfin login is not offered
/// in v2 yet; Soup Identity is the sign-in path.
class SoupApp extends StatefulWidget {
  const SoupApp({
    required this.tailscaleClient,
    this.jellyfinClientFactory = const DefaultJellyfinClientFactory(),
    this.sessionStore = const SecureSessionStore(),
    this.soupSessionStore = const SecureSoupSessionStore(),
    this.soupIdentityFlags = SoupIdentityFlags.fromEnvironment,
    this.soupIdentityClient,
    this.connectionStore,
    this.discoveryService,
    super.key,
  });

  final TailscaleClient tailscaleClient;
  final JellyfinClientFactory jellyfinClientFactory;
  final SessionStore sessionStore;
  final SoupSessionStore soupSessionStore;
  final SoupIdentityFlags soupIdentityFlags;
  final SoupIdentityClient? soupIdentityClient;
  final ConnectionPreferencesStore? connectionStore;
  final JellyfinDiscoveryService? discoveryService;

  @override
  State<SoupApp> createState() => _SoupAppState();
}

class _SoupAppState extends State<SoupApp> {
  late final ConnectivityViewModel _connectivity;
  late final SoupDeviceLinkViewModel _soupAuth;
  Object? _navigationIdentity;
  GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  bool _adoptedTransport = false;
  bool _adoptedJellyfin = false;

  @override
  void initState() {
    super.initState();
    _connectivity = ConnectivityViewModel(
      widget.tailscaleClient,
      jellyfinClientFactory: widget.jellyfinClientFactory,
      sessionStore: widget.sessionStore,
      connectionStore:
          widget.connectionStore ?? SharedPreferencesConnectionStore(),
      discoveryService: widget.discoveryService,
    )..initialize();
    final flags = widget.soupIdentityFlags;
    final client =
        widget.soupIdentityClient ??
        (flags.useMock
            ? MockSoupIdentityClient()
            : HttpSoupIdentityClient(baseUrl: flags.baseUri));
    _soupAuth = SoupDeviceLinkViewModel(
      client: client,
      sessionStore: widget.soupSessionStore,
      jellyfinSessionStore: widget.sessionStore,
      jellyfinApiProvider: () => _connectivity.authenticatedApi(),
      tailscaleClient: widget.tailscaleClient,
      connectTransportGrants: flags.connectTransportGrants,
    )..initialize();
  }

  @override
  void dispose() {
    _connectivity.dispose();
    _soupAuth.dispose();
    super.dispose();
  }

  Future<void> _signOut() async {
    await _connectivity.signOut();
    await _soupAuth.clearSession();
    _adoptedTransport = false;
    _adoptedJellyfin = false;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_connectivity, _soupAuth]),
      builder: (context, _) {
        final session = _connectivity.session;
        final authenticated =
            _connectivity.phase == SetupPhase.ready && session != null;
        // Routes belong to one account and transport; drop them on change.
        final identity = authenticated
            ? (session.serverId, session.userId, _connectivity.transportRevision)
            : null;
        if (identity != _navigationIdentity) {
          _navigationIdentity = identity;
          _navigatorKey = GlobalKey<NavigatorState>();
        }
        return MaterialApp(
          navigatorKey: _navigatorKey,
          title: 'Soup',
          debugShowCheckedModeBanner: false,
          theme: SoupTheme.dark,
          home: _home(session, authenticated),
        );
      },
    );
  }

  Widget _home(JellyfinSession? session, bool authenticated) {
    if (!_connectivity.initialized || !_soupAuth.initialized) {
      final error = _connectivity.initializationError ?? _soupAuth.error;
      return StatusScreen(
        title: error == null ? 'Opening Soup' : 'Let’s try that again',
        message: error ?? 'Loading your saved setup…',
        busy: error == null,
        onRetry: error == null
            ? null
            : () {
                _connectivity.initialize();
                unawaited(_soupAuth.initialize());
              },
      );
    }
    if (_soupAuth.showsAuthShell) {
      if (_soupAuth.phase == SoupDeviceLinkPhase.idle &&
          _soupAuth.session == null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => unawaited(_soupAuth.startDeviceLink()),
        );
      }
      return LoginScreen(viewModel: _soupAuth);
    }
    if (_soupAuth.transportConnected && !_adoptedTransport) {
      _adoptedTransport = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(_connectivity.adoptSoupAuthKeyTransport()),
      );
    }
    final soupJellyfin = _soupAuth.jellyfinSession;
    if (soupJellyfin != null && !_adoptedJellyfin) {
      _adoptedJellyfin = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(_connectivity.adoptSoupJellyfinSession(soupJellyfin)),
      );
    }
    if (soupJellyfin != null && session == null) {
      return const StatusScreen(
        title: 'Opening Soup',
        message: 'Finishing your Jellyfin sign-in…',
        busy: true,
      );
    }
    if (session != null && !authenticated) {
      final status = _connectivity.status;
      return StatusScreen(
        title: 'Reconnecting to Tailscale',
        message: status.authorizationUrl != null
            ? 'Scan to reconnect. Your Jellyfin sign-in is saved.'
            : status.phase == TailscaleConnectionPhase.awaitingApproval
            ? 'Approve this device in Tailscale. Your Jellyfin sign-in is saved.'
            : _connectivity.connecting
            ? 'We’ll open your library as soon as you’re connected.'
            : 'Check your connection, then try again.',
        busy: _connectivity.connecting,
        authorizationUrl: status.authorizationUrl,
        onRetry: _connectivity.connecting ? null : _connectivity.reconnectSession,
      );
    }
    if (authenticated && session != null) {
      return HomeScreen(session: session, onSignOut: _signOut);
    }
    // Soup auth finished without a Jellyfin session (exchange skipped).
    return const StatusScreen(
      title: 'Opening Soup',
      message: 'Connecting to your server…',
      busy: true,
    );
  }
}

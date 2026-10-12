import 'dart:async';

import 'package:flutter/material.dart';
import 'package:soup_core/soup_core.dart';
import 'package:soup_identity/soup_identity.dart';
import 'package:soup_tailscale/soup_tailscale.dart';

import 'config.dart' as config;
import 'features/auth/direct_login_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/shell/authenticated_root.dart';
import 'features/shared/status_screen.dart';
import 'form_factor.dart';
import 'ui/theme/soup_theme.dart';
import 'ui/touch/touch_frame.dart';
import 'ui/widgets/design_scale.dart';

/// Auth gate shared in shape with the v1 app: loading → sign-in home →
/// Tailscale reconnect → authenticated. The sign-in home offers Soup
/// device-link and discovered servers side by side; picking a server or
/// entering an address opens the direct Jellyfin form.
class SoupApp extends StatefulWidget {
  const SoupApp({
    required this.tailscaleClient,
    this.jellyfinClientFactory = const DefaultJellyfinClientFactory(),
    this.sessionStore = const SecureSessionStore(),
    this.soupSessionStore = const SecureSoupSessionStore(),
    this.soupIdentityFlags = config.soupIdentityFlags,
    this.soupIdentityClient,
    this.connectionStore,
    this.authPathStore,
    this.discoveryService,
    this.formFactor = FormFactor.tv,
    super.key,
  });

  final TailscaleClient tailscaleClient;
  final JellyfinClientFactory jellyfinClientFactory;
  final SessionStore sessionStore;
  final SoupSessionStore soupSessionStore;
  final SoupIdentityFlags soupIdentityFlags;
  final SoupIdentityClient? soupIdentityClient;
  final ConnectionPreferencesStore? connectionStore;
  final AuthPathPreferencesStore? authPathStore;
  final JellyfinDiscoveryService? discoveryService;
  final FormFactor formFactor;

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
  late final AuthPathPreferencesStore _authPathStore;
  AuthPath _authPath = AuthPath.soup;
  bool _authPathReady = false;

  @override
  void initState() {
    super.initState();
    _authPathStore = widget.authPathStore ?? SharedPreferencesAuthPathStore();
    unawaited(_loadAuthPath());
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
      // A roster's Tailscale grant can't be joined without libtailscale.
      connectTransportGrants:
          flags.connectTransportGrants &&
          widget.tailscaleClient is! UnavailableTailscaleClient,
    )..initialize();
    _traceStateChanges();
  }

  Future<void> _loadAuthPath() async {
    AuthPath? saved;
    try {
      saved = await _authPathStore.read();
    } on Object {
      saved = null;
    }
    if (!mounted) return;
    setState(() {
      _authPath = saved ?? AuthPath.soup;
      _authPathReady = true;
    });
  }

  Future<void> _chooseDirectLogin() async {
    await _authPathStore.write(AuthPath.direct);
    if (!mounted) return;
    setState(() => _authPath = AuthPath.direct);
  }

  Future<void> _chooseSoupInvite() async {
    await _authPathStore.write(AuthPath.soup);
    if (!mounted) return;
    setState(() => _authPath = AuthPath.soup);
    if (_soupAuth.session == null &&
        _soupAuth.phase != SoupDeviceLinkPhase.waiting &&
        _soupAuth.phase != SoupDeviceLinkPhase.starting) {
      unawaited(_soupAuth.startDeviceLink());
    }
  }

  // Debug-only trace of the sign-in/transport state machine (visible in logcat).
  void _traceStateChanges() {
    assert(() {
      _soupAuth.addListener(
        () => debugPrint(
          '[soup] auth phase=${_soupAuth.phase.name} transport=${_soupAuth.transportConnected} '
          'err=${_soupAuth.error ?? _soupAuth.transportError ?? _soupAuth.exchangeError}',
        ),
      );
      _connectivity.addListener(
        () => debugPrint(
          '[soup] conn phase=${_connectivity.phase.name} ts=${_connectivity.status.phase.name} '
          'connecting=${_connectivity.connecting} session=${_connectivity.session != null} '
          'err=${_connectivity.error ?? _connectivity.initializationError}',
        ),
      );
      return true;
    }());
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
            ? (
                session.serverId,
                session.userId,
                _connectivity.transportRevision,
              )
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
          builder: (context, child) => FormFactorScope(
            value: widget.formFactor,
            child: widget.formFactor.isTouch
                ? TouchFrame(child: child!)
                : DesignScale(child: child!),
          ),
          home: _home(session, authenticated),
        );
      },
    );
  }

  Widget _home(JellyfinSession? session, bool authenticated) {
    if (!_connectivity.initialized ||
        !_soupAuth.initialized ||
        !_authPathReady) {
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
    // Sign-in home: Soup QR, discovered servers and Tailscale. The Jellyfin
    // address/credentials form takes over once a server is picked or typed.
    final directForm =
        _connectivity.phase == SetupPhase.credentials ||
        (_connectivity.phase == SetupPhase.server &&
            !_connectivity.showingServerDiscovery);
    if (_soupAuth.showsAuthShell &&
        !directForm &&
        (session == null || _authPath != AuthPath.direct)) {
      if (_soupAuth.phase == SoupDeviceLinkPhase.idle &&
          _soupAuth.session == null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => unawaited(_soupAuth.startDeviceLink()),
        );
      }
      return LoginScreen(
        viewModel: _soupAuth,
        connectivity: _connectivity,
        onDirectStep: _chooseDirectLogin,
      );
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
            ? '${widget.formFactor.isTouch ? 'Sign in to Tailscale' : 'Scan'} to reconnect. Your Jellyfin sign-in is saved.'
            : status.phase == TailscaleConnectionPhase.awaitingApproval
            ? 'Approve this device in Tailscale. Your Jellyfin sign-in is saved.'
            : _connectivity.connecting
            ? 'We’ll open your library as soon as you’re connected.'
            : 'Check your connection, then try again.',
        busy: _connectivity.connecting,
        authorizationUrl: status.authorizationUrl,
        onRetry: _connectivity.connecting
            ? null
            : _connectivity.reconnectSession,
      );
    }
    if (authenticated && session != null) {
      return AuthenticatedRoot(
        key: ValueKey('${session.serverId}:${session.userId}'),
        connectivity: _connectivity,
        soupAuth: _soupAuth,
        session: session,
        onSignOut: _signOut,
      );
    }
    // The Jellyfin address/credentials form (and Quick Connect), or the
    // Tailscale step when no sign-in home applies.
    return DirectLoginScreen(
      viewModel: _connectivity,
      onUseSoupInvite: () => unawaited(_chooseSoupInvite()),
    );
  }
}

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:soup_core/soup_core.dart';
import 'package:soup_identity/soup_identity.dart' show DeviceLinkStart;
import 'package:soup_tailscale/soup_tailscale.dart';

import '../../form_factor.dart';
import '../../ui/theme/soup_tokens.dart';
import '../../ui/touch/sign_in_link.dart';
import '../../ui/widgets/focusable.dart';
import '../../ui/widgets/soup_button.dart' show SoupButtonStyle;
import '../../ui/widgets/soup_wordmark.dart';
import 'auth_button.dart';
import 'poster_wall.dart';

const _danger = Color(0xFFFF6B5E);
const _tileFill = Color(0x14FFFFFF);
const _tileFocused = Color(0xCC48484E);

/// Sign-in home (web design "A · Glass Stack"): the Soup device-link QR, the
/// Jellyfin servers discovered on this network (and the tailnet, once
/// Tailscale is on), "Enter address", and a Tailscale button that swaps the
/// card for Tailscale's own sign-in.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    required this.viewModel,
    required this.connectivity,
    this.onDirectStep,
    super.key,
  });

  final SoupDeviceLinkViewModel viewModel;
  final ConnectivityViewModel connectivity;

  /// Runs before handing off to the Jellyfin address/credentials form, so a
  /// direct sign-in is remembered across restarts.
  final Future<void> Function()? onDirectStep;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with WidgetsBindingObserver {
  final _enterFocus = FocusNode(debugLabel: 'enter server address');
  final _tailscaleFocus = FocusNode(debugLabel: 'Tailscale');
  final _tailscaleBackFocus = FocusNode(debugLabel: 'Tailscale back');
  final _searchFocus = FocusNode(debugLabel: 'search servers again');
  final _serverNodes = <String, FocusNode>{};

  bool _tailscaleOpen = false;
  bool _tailscaleHint = false;
  late bool _wasConnected;
  late int _serverCount;

  ConnectivityViewModel get _conn => widget.connectivity;

  /// Phones open sign-in links instead of showing QR codes to scan.
  bool get _touch => context.isTouch;

  @override
  void initState() {
    super.initState();
    _wasConnected = _conn.tailscaleConnected;
    _serverCount = _servers.length;
    _conn.addListener(_connectivityChanged);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _advance());
  }

  /// No QR-code polling while the app is in the background.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.viewModel.setForeground(state == AppLifecycleState.resumed);
  }

  @override
  void didUpdateWidget(covariant LoginScreen old) {
    super.didUpdateWidget(old);
    if (old.connectivity != _conn) {
      old.connectivity.removeListener(_connectivityChanged);
      _conn.addListener(_connectivityChanged);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _conn.removeListener(_connectivityChanged);
    for (final node in [
      _enterFocus,
      _tailscaleFocus,
      _tailscaleBackFocus,
      _searchFocus,
      ..._serverNodes.values,
    ]) {
      node.dispose();
    }
    super.dispose();
  }

  /// Discovery only runs on the server step, so move a fresh (or freshly
  /// connected) setup there as soon as its transport allows.
  void _advance() {
    if (!mounted) return;
    final c = _conn;
    if (c.initialized &&
        c.session == null &&
        c.phase == SetupPhase.connection &&
        c.canContinueConnection &&
        c.error == null) {
      unawaited(c.continueConnection());
    }
  }

  void _connectivityChanged() {
    _advance();
    final connected = _conn.tailscaleConnected;
    if (connected && !_wasConnected && _tailscaleOpen) {
      // Signed in to Tailscale: back to the card, where tailnet servers appear.
      setState(() => _tailscaleOpen = false);
      _focusLater(_tailscaleFocus);
    }
    _wasConnected = connected;
    final servers = _servers;
    if (_serverCount == 0 && servers.isNotEmpty) {
      // First result: jump from the "Enter address" fallback to the server,
      // but never pull focus from somewhere the user moved it themselves.
      final primary = FocusManager.instance.primaryFocus;
      if (primary == null ||
          primary == _enterFocus ||
          primary == _searchFocus) {
        _focusLater(_serverNode(servers.first.info.id));
      }
    }
    _serverCount = servers.length;
  }

  void _focusLater(FocusNode node) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && node.context != null) node.requestFocus();
    });
  }

  FocusNode _serverNode(String id) =>
      _serverNodes.putIfAbsent(id, () => FocusNode(debugLabel: 'server $id'));

  List<DiscoveredJellyfinServer> get _servers =>
      _conn.phase == SetupPhase.server && _conn.showingServerDiscovery
      ? _conn.discovery.servers
      : const [];

  // ── actions ─────────────────────────────────────────────────────────────
  Future<void> _pick(DiscoveredJellyfinServer server) async {
    if (_conn.isBusy || !server.info.supportsSoup) return;
    await widget.onDirectStep?.call();
    await _conn.connectDiscoveredServer(server);
  }

  Future<void> _enterAddress() async {
    if (_conn.isBusy || _conn.phase != SetupPhase.server) return;
    await widget.onDirectStep?.call();
    _conn.enterServerManually();
  }

  void _openTailscale() {
    setState(() => _tailscaleOpen = true);
    if (!_conn.tailscaleEnabled) {
      unawaited(_conn.setTailscaleEnabled(true));
    } else if (!_conn.tailscaleConnected && !_conn.connecting) {
      unawaited(_conn.retryTailscale());
    }
    _focusLater(_tailscaleBackFocus);
  }

  /// Leaving an unfinished sign-in turns Tailscale back off, so local
  /// discovery resumes; a connected tailnet stays on unless [turnOff].
  void _closeTailscale({bool turnOff = false}) {
    setState(() => _tailscaleOpen = false);
    if (turnOff || !_conn.tailscaleConnected) {
      unawaited(_conn.setTailscaleEnabled(false));
    }
    _focusLater(_tailscaleFocus);
  }

  // ── build ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_tailscaleOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _tailscaleOpen) _closeTailscale();
      },
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            const PosterWall(),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: ListenableBuilder(
                  listenable: Listenable.merge([widget.viewModel, _conn]),
                  builder: (context, _) =>
                      _tailscaleOpen ? _tailscaleCard() : _mainColumn(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mainColumn() {
    final busy = _soupBusyText();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Card(
          width: 615,
          padding: _touch
              ? const EdgeInsets.fromLTRB(20, 24, 20, 24)
              : const EdgeInsets.fromLTRB(48, 39, 48, 42),
          child: busy != null
              ? _busy(busy)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _wordmark(),
                    const SizedBox(height: 21),
                    _soupBlock(),
                    const SizedBox(height: 21),
                    _divider(),
                    const SizedBox(height: 21),
                    _serverRow(),
                    const SizedBox(height: 12),
                    _actionRow(),
                    if (_conn.error case final error?) ...[
                      const SizedBox(height: 14),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          error,
                          key: const ValueKey('connection-error'),
                          textAlign: TextAlign.center,
                          style: SoupType.style(
                            size: 15,
                            weight: 600,
                            color: _danger,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
        ),
        if (busy == null && !_touch) ...[const SizedBox(height: 21), _hint()],
      ],
    );
  }

  /// Soup sign-in progress after the QR is approved replaces the whole card.
  String? _soupBusyText() => switch (widget.viewModel.phase) {
    SoupDeviceLinkPhase.loadingRoster => 'Loading your servers…',
    SoupDeviceLinkPhase.connectingTransport =>
      'Connecting to your server over Tailscale…',
    SoupDeviceLinkPhase.exchanging ||
    SoupDeviceLinkPhase.ready => 'Signing in to Jellyfin…',
    _ => null,
  };

  Widget _wordmark() => SoupWordmark(size: _touch ? 48 : 66);

  Widget _soupBlock() {
    final model = widget.viewModel;
    switch (model.phase) {
      case SoupDeviceLinkPhase.expired:
        return _soupMessage(
          'Code expired',
          _touch
              ? 'Get a new code to sign in.'
              : 'Get a new code to sign in with your phone.',
          'New code',
        );
      case SoupDeviceLinkPhase.error:
      case SoupDeviceLinkPhase.needsGoogleSignIn:
        var title = model.phase == SoupDeviceLinkPhase.error
            ? 'Something went wrong'
            : 'Sign in again';
        var message =
            model.error ??
            model.exchangeError ??
            'Your Soup session ended. Scan a new code to sign in.';
        // "Can't reach Jeline. Make sure…" reads better as heading + body.
        final split = message.indexOf('. ');
        if (message.startsWith("Can't reach ") && split > 0) {
          title = message.substring(0, split);
          message = message.substring(split + 2);
        }
        return _soupMessage(title, message, 'Try again');
      default:
        break;
    }
    final link = model.phase == SoupDeviceLinkPhase.waiting ? model.link : null;
    if (_touch) return _soupLinkTouch(link);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 198,
          height: 198,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: link == null ? const Color(0x1AFFFFFF) : Colors.white,
            borderRadius: BorderRadius.circular(18),
          ),
          alignment: Alignment.center,
          child: link == null
              ? const _Spinner(size: 28)
              : QrImageView(
                  data: link.verificationUriComplete.toString(),
                  padding: EdgeInsets.zero,
                  semanticsLabel: 'Soup sign-in QR code',
                ),
        ),
        const SizedBox(width: 27),
        SizedBox(
          width: 270,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Scan with your phone',
                style: SoupType.style(size: 26, weight: 800, height: 1.1),
              ),
              const SizedBox(height: 10),
              Text(
                link == null
                    ? 'Getting a sign-in code…'
                    : 'Or go to ${link.verificationUri.host}${link.verificationUri.path} and enter',
                style: SoupType.style(
                  size: 16.5,
                  color: SoupColors.ink2,
                  height: 1.45,
                ),
              ),
              if (link != null) ...[
                const SizedBox(height: 10),
                Text(
                  link.userCode,
                  style: SoupType.style(
                    size: 33,
                    weight: 800,
                    letterSpacing: 4.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Touch: open the device-link page in the browser on this phone.
  Widget _soupLinkTouch(DeviceLinkStart? link) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Sign in with Soup',
        textAlign: TextAlign.center,
        style: SoupType.style(size: 24, weight: 800, height: 1.1),
      ),
      const SizedBox(height: 8),
      Text(
        link == null
            ? 'Getting a sign-in code…'
            : 'Continue in your browser, then come back here.',
        textAlign: TextAlign.center,
        style: SoupType.style(size: 15, color: SoupColors.ink2, height: 1.4),
      ),
      const SizedBox(height: 16),
      if (link == null)
        const Center(child: _Spinner(size: 28))
      else ...[
        SignInLinkButton(
          url: link.verificationUriComplete,
          label: 'Continue in browser',
        ),
        const SizedBox(height: 10),
        Text(
          'Code ${link.userCode}',
          textAlign: TextAlign.center,
          style: SoupType.style(
            size: 15,
            weight: 700,
            color: SoupColors.muted,
            letterSpacing: 1.5,
          ),
        ),
      ],
    ],
  );

  Widget _soupMessage(String title, String body, String action) => Column(
    children: [
      Text(
        title,
        textAlign: TextAlign.center,
        style: SoupType.style(size: 28, weight: 800, letterSpacing: -0.6),
      ),
      const SizedBox(height: 8),
      Text(
        body,
        textAlign: TextAlign.center,
        style: SoupType.style(size: 16.5, color: SoupColors.muted, height: 1.4),
      ),
      const SizedBox(height: 16),
      AuthButton(
        label: action,
        height: 54,
        onPressed: () =>
            unawaited(widget.viewModel.startDeviceLink(newCode: true)),
      ),
    ],
  );

  Widget _divider() {
    final searching = _conn.showingServerDiscovery && _conn.discovery.searching;
    return Row(
      children: [
        const Expanded(child: Divider(color: Color(0x1FFFFFFF), height: 1)),
        const SizedBox(width: 12),
        if (searching) ...[const _Ping(), const SizedBox(width: 10)],
        Flexible(
          flex: 4,
          child: Text(
            _conn.tailscaleConnected
                ? (_touch
                      ? 'Network and tailnet'
                      : 'Servers on your network and tailnet')
                : (_touch
                      ? 'Servers on your network'
                      : 'Jellyfin servers on your network'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SoupType.style(
              size: 15,
              weight: 600,
              color: SoupColors.muted,
            ),
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(child: Divider(color: Color(0x1FFFFFFF), height: 1)),
      ],
    );
  }

  Widget _serverRow() {
    final servers = _servers;
    final searching =
        _conn.discovery.searching || _conn.phase != SetupPhase.server;
    if (servers.isEmpty) {
      return searching ? _searchingTile() : _emptyTile();
    }
    if (_touch) {
      return Column(
        children: [
          for (final (i, server) in servers.take(3).indexed) ...[
            if (i > 0) const SizedBox(height: 10),
            _serverTile(server),
          ],
        ],
      );
    }
    return Row(
      children: [
        for (final (i, server) in servers.take(3).indexed) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: _serverTile(server)),
        ],
      ],
    );
  }

  Widget _serverTile(DiscoveredJellyfinServer server) {
    final supported = server.info.supportsSoup;
    final tailscale = server.sources.contains(DiscoverySource.tailscale);
    final badge = !supported
        ? 'NEEDS 10.11+'
        : tailscale
        ? 'TAILSCALE'
        : 'LOCAL';
    return Opacity(
      opacity: supported ? 1 : 0.5,
      child: Focusable(
        key: ValueKey('discovered-server-${server.info.id}'),
        focusNode: _serverNode(server.info.id),
        radius: SoupRadii.card,
        onActivate: supported && !_conn.isBusy
            ? () => unawaited(_pick(server))
            : null,
        builder: (context, focused) => Semantics(
          button: true,
          label: '${server.info.name}, $badge',
          child: ExcludeSemantics(
            child: Container(
              height: 75,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: focused ? _tileFocused : _tileFill,
                borderRadius: BorderRadius.circular(SoupRadii.card),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    server.info.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SoupType.style(size: 17, weight: 800),
                  ),
                  const SizedBox(height: 6),
                  _Badge(badge, accent: tailscale && supported),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _searchingTile() => Container(
    height: 75,
    padding: const EdgeInsets.symmetric(horizontal: 18),
    decoration: BoxDecoration(
      color: const Color(0x0DFFFFFF),
      borderRadius: BorderRadius.circular(SoupRadii.card),
    ),
    child: Row(
      children: [
        const _Spinner(size: 20),
        const SizedBox(width: 14),
        Text(
          'Looking for servers…',
          style: SoupType.style(size: 17, weight: 700, color: SoupColors.ink2),
        ),
      ],
    ),
  );

  Widget _emptyTile() => Focusable(
    focusNode: _searchFocus,
    radius: SoupRadii.card,
    onActivate: _conn.isBusy ? null : () => _conn.searchServers(again: true),
    builder: (context, focused) => Semantics(
      button: true,
      label: 'No servers found yet. Search again',
      child: ExcludeSemantics(
        child: Container(
          height: 75,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: focused ? _tileFocused : const Color(0x0DFFFFFF),
            borderRadius: BorderRadius.circular(SoupRadii.card),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.wifi_off_rounded,
                size: 26,
                color: SoupColors.muted,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'No servers found yet',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SoupType.style(size: 17, weight: 800),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _touch
                          ? 'Tap to search again'
                          : 'Is this TV on the same Wi-Fi?',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SoupType.style(
                        size: 14,
                        weight: 600,
                        color: SoupColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (!_touch)
                Text(
                  'Search again',
                  style: SoupType.style(
                    size: 15,
                    weight: 700,
                    color: SoupColors.ink2,
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _actionRow() {
    final canEnter = _conn.phase == SetupPhase.server && !_conn.isBusy;
    return Row(
      children: [
        Expanded(
          child: Opacity(
            opacity: canEnter ? 1 : 0.5,
            child: Focusable(
              focusNode: _enterFocus,
              autofocus: true,
              radius: SoupRadii.card,
              onActivate: canEnter ? () => unawaited(_enterAddress()) : null,
              builder: (context, focused) => Semantics(
                button: true,
                label: 'Enter a server address',
                child: ExcludeSemantics(
                  child: CustomPaint(
                    foregroundPainter: focused
                        ? null
                        : const _DashedBorder(radius: SoupRadii.card),
                    child: Container(
                      height: 63,
                      decoration: BoxDecoration(
                        color: focused ? _tileFocused : Colors.transparent,
                        borderRadius: BorderRadius.circular(SoupRadii.card),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_rounded,
                            size: 24,
                            color: focused ? SoupColors.ink : SoupColors.ink2,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Enter address',
                            style: SoupType.style(
                              size: 17,
                              weight: 700,
                              color: focused ? SoupColors.ink : SoupColors.ink2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_conn.tailscaleAvailable) ...[
          const SizedBox(width: 12),
          Focusable(
            key: const ValueKey('tailscale-button'),
            focusNode: _tailscaleFocus,
            radius: SoupRadii.card,
            onFocusChange: (v) => setState(() => _tailscaleHint = v),
            onActivate: _openTailscale,
            builder: (context, focused) => Semantics(
              button: true,
              label: _conn.tailscaleConnected
                  ? 'Tailscale, connected'
                  : 'Use Tailscale',
              child: ExcludeSemantics(
                child: Container(
                  width: 63,
                  height: 63,
                  decoration: BoxDecoration(
                    color: focused ? _tileFocused : _tileFill,
                    borderRadius: BorderRadius.circular(SoupRadii.card),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const _TailscaleMark(size: 24),
                      if (_conn.tailscaleConnected)
                        Positioned(
                          top: 10,
                          right: 10,
                          child: Container(
                            width: 11,
                            height: 11,
                            decoration: BoxDecoration(
                              color: SoupColors.ok,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFF2A2A2D),
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _hint() {
    final text = _tailscaleHint
        ? (_conn.tailscaleConnected
              ? 'Servers on your tailnet are marked TAILSCALE'
              : 'Use Tailscale to reach servers outside your home')
        : 'Pick a server, or scan the code with your phone';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0x4DFFFFFF), width: 1.2),
          ),
          child: Text(
            'OK',
            style: SoupType.style(
              size: 12,
              weight: 800,
              color: SoupColors.ink2,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          text,
          style: SoupType.style(size: 15, weight: 600, color: SoupColors.muted),
        ),
      ],
    );
  }

  Widget _busy(String text) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _wordmark(),
      const SizedBox(height: 28),
      const _Spinner(size: 32),
      const SizedBox(height: 18),
      Text(
        text,
        textAlign: TextAlign.center,
        style: SoupType.style(size: 18, color: SoupColors.ink2),
      ),
    ],
  );

  // ── Tailscale sign-in ───────────────────────────────────────────────────
  Widget _tailscaleCard() {
    final status = _conn.status;
    final url = status.authorizationUrl;
    final connected = _conn.tailscaleConnected;
    final approval = status.phase == TailscaleConnectionPhase.awaitingApproval;
    final failed =
        !_conn.connecting &&
        (status.phase == TailscaleConnectionPhase.failed ||
            status.phase == TailscaleConnectionPhase.disconnected);

    final Widget body;
    if (connected) {
      body = _tailscaleNote(
        icon: const Icon(Icons.check_rounded, color: SoupColors.ok, size: 34),
        title: 'Connected to Tailscale',
        text:
            'Servers on your tailnet show up on the sign-in screen marked TAILSCALE.',
      );
    } else if (url != null &&
        status.phase == TailscaleConnectionPhase.awaitingLogin &&
        _touch) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _step(1, 'Open the Tailscale sign-in page'),
          const SizedBox(height: 12),
          _step(2, 'Sign in, then come back here'),
          const SizedBox(height: 12),
          _step(3, 'If asked, approve this device in the admin console'),
          const SizedBox(height: 20),
          SignInLinkButton(url: url, label: 'Open Tailscale sign-in'),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const _Spinner(size: 18),
              const SizedBox(width: 12),
              Text(
                'Waiting for sign-in',
                key: const ValueKey('connection-status'),
                style: SoupType.style(
                  size: 15,
                  weight: 700,
                  color: SoupColors.muted,
                ),
              ),
            ],
          ),
        ],
      );
    } else if (url != null &&
        status.phase == TailscaleConnectionPhase.awaitingLogin) {
      body = Row(
        children: [
          Container(
            width: 255,
            height: 255,
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(21),
            ),
            child: QrImageView(
              data: url.toString(),
              padding: EdgeInsets.zero,
              semanticsLabel: 'Tailscale sign-in QR code',
            ),
          ),
          const SizedBox(width: 42),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _step(1, 'Scan the code with your phone'),
                const SizedBox(height: 15),
                _step(2, 'Sign in to Tailscale'),
                const SizedBox(height: 15),
                _step(3, 'If asked, approve this TV in the admin console'),
                const SizedBox(height: 24),
                Semantics(
                  liveRegion: true,
                  child: Row(
                    children: [
                      const _Spinner(size: 18),
                      const SizedBox(width: 12),
                      Text(
                        'Waiting for sign-in',
                        key: const ValueKey('connection-status'),
                        style: SoupType.style(
                          size: 16.5,
                          weight: 700,
                          color: SoupColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    } else if (approval) {
      body = _tailscaleNote(
        icon: const _Spinner(size: 30),
        title: 'Waiting for device approval',
        text:
            'You’re signed in to Tailscale. Ask your administrator to approve this ${_touch ? 'device' : 'TV'} in the admin console.',
      );
    } else if (failed) {
      body = _tailscaleNote(
        icon: const Icon(
          Icons.error_outline_rounded,
          color: SoupColors.accent,
          size: 32,
        ),
        title: 'Couldn’t connect to Tailscale',
        text:
            status.detail ??
            _conn.error ??
            'Check your connection and try again.',
      );
    } else {
      body = _tailscaleNote(
        icon: const _Spinner(size: 30),
        title: 'Preparing sign-in…',
        text: 'Your Tailscale sign-in code will appear here.',
      );
    }

    final secondary = connected
        ? ('Turn off Tailscale', () => _closeTailscale(turnOff: true))
        : failed
        ? ('Retry', () => unawaited(_conn.retryTailscale()))
        : url != null
        ? ('Get a new code', () => unawaited(_conn.retryTailscale()))
        : null;

    return _Card(
      width: 780,
      padding: _touch
          ? const EdgeInsets.fromLTRB(20, 24, 20, 24)
          : const EdgeInsets.fromLTRB(48, 42, 48, 42),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _tileFill,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: const _TailscaleMark(size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Connect with Tailscale',
                      style: SoupType.style(
                        size: _touch ? 24 : 36,
                        weight: 800,
                        letterSpacing: -1,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Watch from servers on your tailnet, even away from home.',
                      style: SoupType.style(
                        size: 16.5,
                        weight: 600,
                        color: SoupColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),
          body,
          const SizedBox(height: 30),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              AuthButton(
                label: 'Back',
                height: 57,
                focusNode: _tailscaleBackFocus,
                onPressed: _closeTailscale,
              ),
              if (secondary != null) ...[
                AuthButton(
                  label: secondary.$1,
                  height: 57,
                  style: SoupButtonStyle.glass,
                  onPressed: _conn.isBusy ? null : secondary.$2,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _step(int n, String text) => Row(
    children: [
      Container(
        width: 33,
        height: 33,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: Color(0x1AFFFFFF),
          shape: BoxShape.circle,
        ),
        child: Text('$n', style: SoupType.style(size: 15, weight: 800)),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Text(
          text,
          style: SoupType.style(size: 18, weight: 600, color: SoupColors.ink2),
        ),
      ),
    ],
  );

  Widget _tailscaleNote({
    required Widget icon,
    required String title,
    required String text,
  }) => Semantics(
    liveRegion: true,
    child: Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0x0DFFFFFF),
        borderRadius: BorderRadius.circular(SoupRadii.panel),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 36, height: 36, child: Center(child: icon)),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  key: const ValueKey('connection-status'),
                  style: SoupType.style(size: 22, weight: 800),
                ),
                const SizedBox(height: 6),
                Text(
                  text,
                  style: SoupType.style(
                    size: 16.5,
                    color: SoupColors.muted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Glass-strong card without a backdrop blur: blurring a continuously
/// scrolling poster wall every frame is too heavy for TV GPUs.
class _Card extends StatelessWidget {
  const _Card({
    required this.width,
    required this.padding,
    required this.child,
  });
  final double width;
  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    // Never wider than the screen (phones), less a 12px margin each side.
    width: math.min(width, MediaQuery.sizeOf(context).width - 24),
    padding: padding,
    decoration: BoxDecoration(
      color: const Color(0xEB1E1E20),
      borderRadius: BorderRadius.circular(30),
      border: Border.all(color: const Color(0x1AFFFFFF)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x8C000000),
          blurRadius: 90,
          offset: Offset(0, 45),
        ),
      ],
    ),
    child: child,
  );
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, {required this.accent});
  final String text;
  final bool accent;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: accent ? const Color(0x29FC7814) : const Color(0x14FFFFFF),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      text,
      style: SoupType.style(
        size: 11,
        weight: 800,
        letterSpacing: 0.6,
        color: accent ? const Color(0xFFFD9A4D) : SoupColors.muted,
      ),
    ),
  );
}

class _Spinner extends StatelessWidget {
  const _Spinner({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: const CircularProgressIndicator(
      strokeWidth: 3,
      color: SoupColors.accent,
      backgroundColor: Color(0xFF3A3A3C),
    ),
  );
}

/// Accent dot with an expanding ring while discovery runs.
class _Ping extends StatefulWidget {
  const _Ping();

  @override
  State<_Ping> createState() => _PingState();
}

class _PingState extends State<_Ping> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      unawaited(_controller.repeat());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 8,
    height: 8,
    child: AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeOut.transform(_controller.value);
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Transform.scale(
              scale: 1 + t * 1.6,
              child: Opacity(
                opacity: (1 - t) * 0.7,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    color: SoupColors.accent,
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox.expand(),
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                color: SoupColors.accent,
                shape: BoxShape.circle,
              ),
              child: SizedBox.expand(),
            ),
          ],
        );
      },
    ),
  );
}

/// Tailscale's 3×3 dot mark, drawn in the current ink.
class _TailscaleMark extends StatelessWidget {
  const _TailscaleMark({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: const CustomPaint(painter: _DotsPainter()),
  );
}

class _DotsPainter extends CustomPainter {
  const _DotsPainter();

  // Full-strength dots form the mark; the rest are faint.
  static const _strong = {3, 4, 5, 7};

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / 24;
    for (var i = 0; i < 9; i++) {
      final paint = Paint()
        ..color = SoupColors.ink.withValues(
          alpha: _strong.contains(i) ? 1 : .4,
        );
      canvas.drawCircle(
        Offset((4 + (i % 3) * 8) * unit, (4 + (i ~/ 3) * 8) * unit),
        2.4 * unit,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DotsPainter oldDelegate) => false;
}

class _DashedBorder extends CustomPainter {
  const _DashedBorder({required this.radius});
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x38FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(radius),
        ).deflate(0.75),
      );
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 10) {
        canvas.drawPath(metric.extractPath(d, d + 6), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder oldDelegate) => oldDelegate.radius != radius;
}

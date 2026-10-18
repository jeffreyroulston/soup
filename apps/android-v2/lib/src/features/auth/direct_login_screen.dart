import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:soup_core/soup_core.dart';
import 'package:soup_tailscale/soup_tailscale.dart';

import '../../form_factor.dart';
import '../../ui/theme/soup_tokens.dart';
import '../../ui/touch/sign_in_link.dart';
import '../../ui/widgets/focusable.dart';
import '../../ui/widgets/soup_button.dart' show SoupButtonStyle;
import 'auth_button.dart';
import '../../ui/widgets/soup_text_field.dart';
import 'poster_wall.dart';

const _danger = Color(0xFFFF6B5E);

/// "Sign in with Jellyfin": Tailscale toggle → server (discovery or manual) →
/// credentials / Quick Connect, driven by [ConnectivityViewModel].
class DirectLoginScreen extends StatefulWidget {
  const DirectLoginScreen({
    required this.viewModel,
    this.onUseSoupInvite,
    super.key,
  });

  final ConnectivityViewModel viewModel;

  /// Return to Soup Identity device-link.
  final VoidCallback? onUseSoupInvite;

  @override
  State<DirectLoginScreen> createState() => _DirectLoginScreenState();
}

class _DirectLoginScreenState extends State<DirectLoginScreen>
    with WidgetsBindingObserver {
  final _server = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _switchFocus = FocusNode(debugLabel: 'use Tailscale');
  final _protocolFocus = FocusNode(debugLabel: 'server protocol');
  final _serverFocus = FocusNode(debugLabel: 'Jellyfin server');
  final _usernameFocus = FocusNode(debugLabel: 'Jellyfin username');
  final _passwordFocus = FocusNode(debugLabel: 'Jellyfin password');
  final _nextFocus = FocusNode(debugLabel: 'setup Next');
  final _backFocus = FocusNode(debugLabel: 'setup Back');
  final _manualFocus = FocusNode(debugLabel: 'enter server manually');
  final _retryDiscoveryFocus = FocusNode(debugLabel: 'search servers again');
  final _quickFocus = FocusNode(debugLabel: 'quick connect action');
  final _discoveryNodes = <String, FocusNode>{};
  final _scroll = ScrollController();

  String _protocol = 'https';
  bool _tv = false;
  late SetupPhase _lastPhase;
  late bool _wasConnected;
  late bool _wasInitialized;
  late bool _wasDiscovery;
  bool _wasBusy = false;
  int _focusGeneration = 0;

  ConnectivityViewModel get model => widget.viewModel;

  @override
  void initState() {
    super.initState();
    _lastPhase = model.phase;
    _wasConnected = model.tailscaleConnected;
    _wasInitialized = model.initialized;
    _wasDiscovery = model.showingServerDiscovery;
    _wasBusy = model.isBusy;
    _server.text = model.serverUrl?.toString() ?? '';
    _server.addListener(_serverChanged);
    model.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
    _usernameFocus.addListener(_credentialFocusChanged);
    _passwordFocus.addListener(_credentialFocusChanged);
    unawaited(
      TvTextInput.isTelevision().then((tv) {
        if (mounted) setState(() => _tv = tv);
        _focusStep();
      }),
    );
  }

  @override
  void didUpdateWidget(covariant DirectLoginScreen old) {
    super.didUpdateWidget(old);
    if (old.viewModel != model) {
      old.viewModel.removeListener(_changed);
      model.addListener(_changed);
      _changed();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    model.removeListener(_changed);
    _server.dispose();
    _username.dispose();
    _password.dispose();
    for (final node in [
      _switchFocus,
      _protocolFocus,
      _serverFocus,
      _usernameFocus,
      _passwordFocus,
      _nextFocus,
      _backFocus,
      _manualFocus,
      _retryDiscoveryFocus,
      _quickFocus,
      ..._discoveryNodes.values,
    ]) {
      node.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    model.setForeground(state == AppLifecycleState.resumed);
  }

  // ── focus / state plumbing ──────────────────────────────────────────────
  void _credentialFocusChanged() {
    // Soft keyboards cover Quick Connect, so pause it while typing. On TV the
    // fields are just focus stops and editing happens in a native dialog.
    if (!_tv && (_usernameFocus.hasFocus || _passwordFocus.hasFocus)) {
      model.pauseQuickConnect();
    }
  }

  void _changed() {
    final phaseChanged = model.phase != _lastPhase;
    final connectionChanged = model.tailscaleConnected != _wasConnected;
    final initialized = model.initialized && !_wasInitialized;
    final discoveryChanged = model.showingServerDiscovery != _wasDiscovery;
    final checkFailed =
        _wasBusy &&
        !model.isBusy &&
        model.showingServerDiscovery &&
        model.error != null;
    _wasDiscovery = model.showingServerDiscovery;
    _wasBusy = model.isBusy;
    _lastPhase = model.phase;
    _wasConnected = model.tailscaleConnected;
    _wasInitialized = model.initialized;
    if (phaseChanged || discoveryChanged) {
      _password.clear();
      if (_server.text.isEmpty && model.serverUrl != null) {
        _server.text = model.serverUrl.toString();
      }
    }
    if (phaseChanged ||
        discoveryChanged ||
        checkFailed ||
        initialized ||
        (connectionChanged && model.phase == SetupPhase.connection)) {
      _focusStep();
    }
  }

  void _focusStep({bool retry = false}) {
    final generation = ++_focusGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _focusGeneration) return;
      if (_scroll.hasClients) _scroll.jumpTo(0);
      switch (model.phase) {
        case SetupPhase.connection:
          (!model.tailscaleAvailable ||
                      model.tailscaleConnected && model.canContinueConnection
                  ? _nextFocus
                  : _switchFocus)
              .requestFocus();
        case SetupPhase.server:
          if (model.showingServerDiscovery) {
            final firstSupported = model.discovery.servers
                .where((s) => s.info.supportsSoup)
                .map((s) => _discoveryNodes[s.info.id])
                .whereType<FocusNode>()
                .where((n) => n.context != null)
                .firstOrNull;
            (firstSupported ?? _manualFocus).requestFocus();
          } else {
            _serverFocus.requestFocus();
          }
        case SetupPhase.credentials:
          if (!_tv && !retry) return;
          (retry && _username.text.trim().isNotEmpty
                  ? _passwordFocus
                  : _usernameFocus)
              .requestFocus();
        case SetupPhase.ready:
          break;
      }
    });
  }

  FocusNode _discoveryNode(String id) => _discoveryNodes.putIfAbsent(
    id,
    () => FocusNode(debugLabel: 'server $id'),
  );

  /// Typing or pasting `https://host` moves the scheme onto the protocol chip.
  void _serverChanged() {
    final value = _server.value;
    final prefix = RegExp(
      r'^\s*(https?)://',
      caseSensitive: false,
    ).firstMatch(value.text);
    if (prefix == null) return;
    final protocol = prefix.group(1)!.toLowerCase();
    final removed = prefix.end;
    final address = value.text.substring(removed);
    int shift(int offset) => (offset - removed).clamp(0, address.length);
    _server.value = TextEditingValue(
      text: address,
      selection: value.selection.isValid
          ? TextSelection(
              baseOffset: shift(value.selection.baseOffset),
              extentOffset: shift(value.selection.extentOffset),
            )
          : TextSelection.collapsed(offset: address.length),
    );
    if (_protocol != protocol) setState(() => _protocol = protocol);
  }

  // ── actions ─────────────────────────────────────────────────────────────
  void _back() {
    if (model.isBusy && model.phase != SetupPhase.credentials) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _password.clear();
    if (model.phase == SetupPhase.connection) {
      if (widget.onUseSoupInvite != null) {
        widget.onUseSoupInvite!();
      } else {
        unawaited(SystemNavigator.pop());
      }
      return;
    }
    model.back();
  }

  Future<void> _next() async {
    if (model.isBusy) return;
    final phase = model.phase;
    FocusManager.instance.primaryFocus?.unfocus();
    switch (phase) {
      case SetupPhase.connection:
        await model.continueConnection();
      case SetupPhase.server:
        final address = _server.text.trim();
        await model.checkServer(
          address.isEmpty || address.contains('://')
              ? address
              : '$_protocol://$address',
        );
      case SetupPhase.credentials:
        final password = _password.text;
        _password.clear();
        await model.signIn(username: _username.text, password: password);
      case SetupPhase.ready:
        break;
    }
    // Validation or network failures leave the step in place; restore a useful
    // focus stop rather than dropping focus into the root scope.
    if (mounted && model.phase == phase) _focusStep(retry: true);
  }

  void _resumeQuickConnect({bool newCode = false}) {
    if (!_tv) FocusManager.instance.primaryFocus?.unfocus();
    unawaited(model.startQuickConnect(newCode: newCode));
  }

  // ── build ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) {
      final phase = model.phase;
      final wide = phase == SetupPhase.credentials;
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _back();
        },
        child: Scaffold(
          resizeToAvoidBottomInset: !_tv,
          body: Stack(
            fit: StackFit.expand,
            children: [
              const PosterWall(),
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: wide ? 900 : 640),
                  child: Container(
                    margin: EdgeInsets.all(context.isTouch ? 12 : 24),
                    padding: context.isTouch
                        ? const EdgeInsets.fromLTRB(20, 22, 20, 20)
                        : const EdgeInsets.fromLTRB(36, 30, 36, 28),
                    decoration: BoxDecoration(
                      color: const Color(0xEB1E1E20),
                      borderRadius: BorderRadius.circular(SoupRadii.spotlight),
                      border: Border.all(color: SoupColors.faint),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _header(),
                        const SizedBox(height: 18),
                        Flexible(
                          child: SingleChildScrollView(
                            controller: _scroll,
                            child: AnimatedSwitcher(
                              duration: MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : const Duration(milliseconds: 200),
                              child: KeyedSubtree(
                                key: ValueKey((
                                  phase,
                                  model.showingServerDiscovery,
                                )),
                                child: _body(context),
                              ),
                            ),
                          ),
                        ),
                        if (model.error case final error?) ...[
                          const SizedBox(height: 12),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              error,
                              key: const ValueKey('connection-error'),
                              style: SoupType.style(
                                size: 16,
                                weight: 600,
                                color: _danger,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 22),
                        _footer(),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _header() {
    final (step, label, title, subtitle) = switch (model.phase) {
      SetupPhase.connection => (
        1,
        'Connection',
        'Connect to Jellyfin',
        model.tailscaleAvailable
            ? 'Optionally use Tailscale, then continue.'
            : 'Soup connects directly to your Jellyfin server.',
      ),
      SetupPhase.server => (
        2,
        'Server',
        'Find your server',
        'Choose a Jellyfin server or enter its address.',
      ),
      SetupPhase.credentials => (
        3,
        'Sign in',
        'Sign in to ${model.serverInfo?.name ?? 'Jellyfin'}',
        model.serverUrl?.toString() ?? '',
      ),
      SetupPhase.ready => (3, 'Sign in', 'You’re in', 'Your library is ready.'),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'STEP $step OF 3 · ${label.toUpperCase()}',
          style: SoupType.style(
            size: 13,
            weight: 800,
            color: SoupColors.muted,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: SoupType.style(
            size: context.isTouch ? 28 : 38,
            weight: 800,
            letterSpacing: -1,
          ),
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: SoupType.style(size: 16, color: SoupColors.muted),
          ),
        ],
      ],
    );
  }

  Widget _body(BuildContext context) => switch (model.phase) {
    SetupPhase.connection => _connectionStep(),
    SetupPhase.server when model.showingServerDiscovery => _discoveryStep(),
    SetupPhase.server => _manualServerStep(),
    SetupPhase.credentials => _credentialsStep(),
    SetupPhase.ready => Text(
      'Your library is ready.',
      style: SoupType.style(size: 18, color: SoupColors.muted),
    ),
  };

  // ── step 1: connection ──────────────────────────────────────────────────
  Widget _connectionStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (model.tailscaleAvailable)
        _SwitchTile(
          key: const ValueKey('tailscale-toggle'),
          focusNode: _switchFocus,
          title: 'Use Tailscale',
          subtitle: 'Optional · Use your private network',
          value: model.tailscaleEnabled,
          onChanged: model.initialized && !model.isBusy
              ? (v) => unawaited(model.setTailscaleEnabled(v))
              : null,
        ),
      if (!model.tailscaleEnabled) ...[
        const SizedBox(height: 18),
        Text(
          'Select Next to connect directly to Jellyfin.',
          style: SoupType.style(size: 16, color: SoupColors.muted),
        ),
      ] else ...[
        const SizedBox(height: 18),
        _tailscaleArea(),
      ],
    ],
  );

  Widget _tailscaleArea() {
    final status = model.status;
    final url = status.authorizationUrl;
    if (status.phase == TailscaleConnectionPhase.awaitingLogin &&
        url != null &&
        context.isTouch) {
      // A phone can't scan its own screen: open the sign-in page instead.
      return Column(
        key: const ValueKey('tailscale-authorization'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SignInLinkButton(url: url, label: 'Open Tailscale sign-in'),
          const SizedBox(height: 10),
          Semantics(
            liveRegion: true,
            child: Text(
              'Waiting for sign-in',
              key: const ValueKey('connection-status'),
              textAlign: TextAlign.center,
              style: SoupType.style(size: 14, color: SoupColors.muted),
            ),
          ),
          const SizedBox(height: 10),
          _button(
            'Get a new link',
            model.isBusy ? null : model.retryTailscale,
            style: SoupButtonStyle.glass,
            height: 48,
            expand: true,
          ),
        ],
      );
    }
    if (status.phase == TailscaleConnectionPhase.awaitingLogin && url != null) {
      return Row(
        key: const ValueKey('tailscale-authorization'),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: QrImageView(
              data: url.toString(),
              size: 164,
              semanticsLabel: 'Tailscale sign-in QR code',
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Scan to sign in',
                  style: SoupType.style(size: 20, weight: 800),
                ),
                const SizedBox(height: 8),
                Text(
                  'Use another device to sign in to Tailscale.',
                  style: SoupType.style(
                    size: 16,
                    color: SoupColors.muted,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    'Waiting for sign-in',
                    key: const ValueKey('connection-status'),
                    style: SoupType.style(size: 14, color: SoupColors.muted),
                  ),
                ),
                const SizedBox(height: 12),
                _button(
                  'Get a new code',
                  model.isBusy ? null : model.retryTailscale,
                  height: 48,
                ),
              ],
            ),
          ),
        ],
      );
    }
    if (model.tailscaleConnected) {
      return Semantics(
        liveRegion: true,
        child: Container(
          key: const ValueKey('tailscale-connected'),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: SoupColors.ok.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(SoupRadii.card),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: SoupColors.ok.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, color: SoupColors.ok, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Connected to Tailscale',
                      key: const ValueKey('connection-status'),
                      style: SoupType.style(size: 20, weight: 800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Select Next to find your Jellyfin server.',
                      style: SoupType.style(size: 16, color: SoupColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    final failed =
        status.phase == TailscaleConnectionPhase.failed ||
        status.phase == TailscaleConnectionPhase.disconnected;
    final approval = status.phase == TailscaleConnectionPhase.awaitingApproval;
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (failed)
            const Icon(Icons.error_outline, color: SoupColors.accent, size: 28)
          else
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: SoupColors.accent,
                backgroundColor: Color(0xFF3A3A3C),
              ),
            ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  failed
                      ? 'Unable to connect'
                      : approval
                      ? 'Waiting for device approval'
                      : 'Preparing sign-in…',
                  key: const ValueKey('connection-status'),
                  style: SoupType.style(size: 20, weight: 800),
                ),
                const SizedBox(height: 6),
                Text(
                  failed
                      ? 'Try again, or turn off Tailscale to connect directly.'
                      : approval
                      ? 'Ask your administrator to approve this device in Tailscale. You can continue once it is approved.'
                      : 'Your sign-in code will appear here.',
                  style: SoupType.style(
                    size: 16,
                    color: SoupColors.muted,
                    height: 1.4,
                  ),
                ),
                if (failed) ...[
                  const SizedBox(height: 12),
                  _button(
                    'Retry',
                    model.isBusy ? null : model.retryTailscale,
                    height: 48,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── step 2: server ──────────────────────────────────────────────────────
  Widget _discoveryStep() {
    final snapshot = model.discovery;
    final message = snapshot.searching
        ? 'Finding your Jellyfin server…'
        : switch (snapshot.phase) {
            DiscoveryPhase.unavailable =>
              'Discovery is unavailable. You can still enter your server address.',
            DiscoveryPhase.partial =>
              snapshot.servers.isEmpty
                  ? 'No servers found yet. The search could not check everything.'
                  : 'Some devices could not be checked.',
            _ =>
              snapshot.servers.isEmpty
                  ? 'No servers found. Try again or enter your server address.'
                  : snapshot.servers.length == 1
                  ? 'Your next watch is waiting.'
                  : 'Choose where you’d like to watch.',
          };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          child: Row(
            children: [
              if (snapshot.searching) ...[
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: SoupColors.accent,
                    backgroundColor: Color(0xFF3A3A3C),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  message,
                  key: const ValueKey('server-discovery-status'),
                  style: SoupType.style(size: 16, color: SoupColors.muted),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        for (final server in snapshot.servers) ...[
          _serverTile(server),
          const SizedBox(height: 12),
        ],
        if (!snapshot.searching)
          Align(
            alignment: Alignment.centerLeft,
            child: _button(
              'Search again',
              model.isBusy
                  ? null
                  : () {
                      _manualFocus.requestFocus();
                      model.searchServers(again: true);
                    },
              style: SoupButtonStyle.glass,
              height: 48,
              focusNode: _retryDiscoveryFocus,
              key: const ValueKey('server-discovery-retry'),
            ),
          ),
      ],
    );
  }

  Widget _serverTile(DiscoveredJellyfinServer server) {
    final supported = server.info.supportsSoup;
    final enabled = supported && !model.isBusy;
    final source = !supported
        ? 'Requires Jellyfin 10.11 or newer'
        : server.sources.contains(DiscoverySource.tailscale)
        ? 'TAILSCALE'
        : 'LOCAL NETWORK';
    return Focusable(
      key: ValueKey('discovered-server-${server.info.id}'),
      focusNode: supported ? _discoveryNode(server.info.id) : null,
      onActivate: enabled ? () => model.connectDiscoveredServer(server) : null,
      builder: (context, focused) => Opacity(
        opacity: supported ? 1 : 0.5,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: focused ? const Color(0x2EFFFFFF) : const Color(0x14FFFFFF),
            borderRadius: BorderRadius.circular(SoupRadii.card),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.video_library_outlined,
                size: 28,
                color: SoupColors.ink2,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      server.info.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SoupType.style(size: 20, weight: 800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      server.url.toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SoupType.style(size: 14, color: SoupColors.muted),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      source,
                      style: SoupType.style(
                        size: 12,
                        weight: 800,
                        letterSpacing: 0.6,
                        color: supported ? SoupColors.accent : SoupColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (supported) ...[
                const SizedBox(width: 12),
                Text('Connect', style: SoupType.style(size: 16, weight: 700)),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward, size: 20),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _manualServerStep() => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Focusable(
        key: const ValueKey('server-protocol-button'),
        focusNode: _protocolFocus,
        radius: SoupRadii.button,
        scale: 1,
        onActivate: model.isBusy
            ? null
            : () => setState(
                () => _protocol = _protocol == 'https' ? 'http' : 'https',
              ),
        builder: (context, focused) => Semantics(
          label: 'Server protocol',
          button: true,
          child: Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: focused ? const Color(0x2EFFFFFF) : SoupColors.faint,
              borderRadius: BorderRadius.circular(SoupRadii.button),
            ),
            child: Text(
              '$_protocol://',
              style: SoupType.style(size: 18, weight: 700),
            ),
          ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: SoupTextField(
          key: const ValueKey('server-url-field'),
          controller: _server,
          focusNode: _serverFocus,
          label: 'Server address',
          hint: model.tailscaleEnabled
              ? 'jellyfin:8096'
              : 'jellyfin.example.com',
          url: true,
          enabled: !model.isBusy,
          onSubmitted: _next,
        ),
      ),
    ],
  );

  // ── step 3: credentials ─────────────────────────────────────────────────
  Widget _credentialsStep() {
    final password = _panel(
      key: const ValueKey('password-panel'),
      children: [
        Text(
          'Username and password',
          style: SoupType.style(size: 20, weight: 800),
        ),
        const SizedBox(height: 16),
        SoupTextField(
          key: const ValueKey('username-field'),
          controller: _username,
          focusNode: _usernameFocus,
          label: 'Username',
          action: TextInputAction.next,
          enabled: !model.isBusy,
          onChanged: (_) {
            if (!_tv) model.pauseQuickConnect();
          },
          onSubmitted: () => _passwordFocus.requestFocus(),
        ),
        const SizedBox(height: 14),
        SoupTextField(
          key: const ValueKey('password-field'),
          controller: _password,
          focusNode: _passwordFocus,
          label: 'Password',
          obscure: true,
          enabled: !model.isBusy,
          onChanged: (_) {
            if (!_tv) model.pauseQuickConnect();
          },
          onSubmitted: _next,
        ),
      ],
    );
    final quick = _panel(
      key: const ValueKey('quick-connect-panel'),
      children: _quickConnectContent(),
    );
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth >= 700
          ? Row(
              key: const ValueKey('sign-in-split-layout'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: quick),
                const SizedBox(width: 20),
                Expanded(child: password),
              ],
            )
          : Column(children: [quick, const SizedBox(height: 16), password]),
    );
  }

  Widget _panel({required Key key, required List<Widget> children}) =>
      Container(
        key: key,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0x14FFFFFF),
          borderRadius: BorderRadius.circular(SoupRadii.card + 4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      );

  List<Widget> _quickConnectContent() {
    final phase = model.quickConnectPhase;
    final code = model.quickConnectCode;
    final waiting = phase == QuickConnectPhase.waiting;
    final paused = phase == QuickConnectPhase.paused;
    final checking =
        phase == QuickConnectPhase.checking || phase == QuickConnectPhase.idle;
    final completing = phase == QuickConnectPhase.completing;
    final unavailable = phase == QuickConnectPhase.unavailable;
    final expired = phase == QuickConnectPhase.expired;
    final message = switch (phase) {
      QuickConnectPhase.idle ||
      QuickConnectPhase.checking => 'Preparing Quick Connect…',
      QuickConnectPhase.waiting => 'Waiting for approval',
      QuickConnectPhase.paused =>
        'Paused while you use another sign-in method.',
      QuickConnectPhase.expired =>
        'This code has expired. Get a new code to continue.',
      QuickConnectPhase.unavailable =>
        'Quick Connect is disabled on this server. You can sign in with your username and password.',
      QuickConnectPhase.error =>
        model.quickConnectError ?? 'Unable to use Quick Connect. Please retry.',
      QuickConnectPhase.completing => 'Approved. Signing in…',
    };
    return [
      Text('Quick Connect', style: SoupType.style(size: 20, weight: 800)),
      const SizedBox(height: 12),
      if (!unavailable) ...[
        Text(
          'On a device already signed in to Jellyfin, open Quick Connect in Settings and enter this code.',
          style: SoupType.style(size: 14, color: SoupColors.muted, height: 1.4),
        ),
        if (code != null) ...[
          const SizedBox(height: 10),
          Semantics(
            label: 'Quick Connect code: ${code.split('').join(' ')}',
            child: ExcludeSemantics(
              child: Text(
                code,
                key: const ValueKey('quick-connect-code'),
                style: SoupType.style(
                  size: 40,
                  weight: 800,
                  color: SoupColors.accent,
                  letterSpacing: 6,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
      ],
      Semantics(
        liveRegion: true,
        child: Text(
          message,
          key: const ValueKey('quick-connect-status'),
          style: SoupType.style(size: 14, color: SoupColors.muted),
        ),
      ),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: _button(
          waiting || expired
              ? 'Get a new code'
              : paused
              ? 'Resume Quick Connect'
              : unavailable
              ? 'Check again'
              : checking
              ? 'Preparing…'
              : completing
              ? 'Signing in…'
              : 'Retry',
          // Repeated presses are ignored until the current request completes.
          model.isBusy && !completing
              ? null
              : () {
                  if (checking || completing) return;
                  _resumeQuickConnect(
                    newCode: waiting || expired || unavailable,
                  );
                },
          style: SoupButtonStyle.glass,
          height: 48,
          focusNode: _quickFocus,
          key: const ValueKey('quick-connect-action'),
        ),
      ),
    ];
  }

  // ── footer ──────────────────────────────────────────────────────────────
  Widget _footer() {
    final phase = model.phase;
    if (model.showingServerDiscovery) {
      return _footerLayout(
        _button(
          'Back',
          model.isBusy ? null : _back,
          style: SoupButtonStyle.glass,
          focusNode: _backFocus,
          expand: context.isTouch,
          key: const ValueKey('onboarding-back-button'),
        ),
        _button(
          model.isBusy ? 'Connecting…' : 'Enter address manually',
          model.isBusy ? null : model.enterServerManually,
          focusNode: _manualFocus,
          expand: true,
          key: const ValueKey('enter-server-manually'),
        ),
      );
    }
    final connection = phase == SetupPhase.connection;
    final enabled = connection
        ? model.canContinueConnection
        : model.initialized && !model.isBusy;
    final label = model.isBusy
        ? switch (phase) {
            SetupPhase.connection => 'Preparing…',
            SetupPhase.server => 'Checking…',
            _ => 'Signing in…',
          }
        : phase == SetupPhase.credentials
        ? 'Sign in'
        : 'Next';
    final Widget? secondary = connection && widget.onUseSoupInvite != null
        ? _button(
            'Use Soup invite instead',
            model.isBusy ? null : widget.onUseSoupInvite,
            style: SoupButtonStyle.glass,
            expand: context.isTouch,
            key: const ValueKey('connectivity-use-soup-invite'),
          )
        : !connection
        ? _button(
            'Back',
            model.isBusy && phase != SetupPhase.credentials ? null : _back,
            style: SoupButtonStyle.glass,
            focusNode: _backFocus,
            expand: context.isTouch,
            key: const ValueKey('onboarding-back-button'),
          )
        : null;
    return _footerLayout(
      secondary,
      _button(
        label,
        enabled ? _next : null,
        focusNode: _nextFocus,
        expand: true,
        key: ValueKey(switch (phase) {
          SetupPhase.connection => 'connection-next-button',
          SetupPhase.server => 'check-server-button',
          SetupPhase.credentials || SetupPhase.ready => 'sign-in-button',
        }),
      ),
    );
  }

  /// Secondary then primary side by side on TV; stacked full-width on touch,
  /// where a phone is too narrow for both.
  Widget _footerLayout(Widget? secondary, Widget primary) {
    if (context.isTouch) {
      return Column(
        key: const ValueKey('setup-footer'),
        children: [
          primary,
          if (secondary != null) ...[const SizedBox(height: 10), secondary],
        ],
      );
    }
    return Row(
      key: const ValueKey('setup-footer'),
      children: [
        if (secondary != null) ...[secondary, const SizedBox(width: 16)],
        Expanded(child: primary),
      ],
    );
  }

  Widget _button(
    String label,
    VoidCallback? onPressed, {
    SoupButtonStyle style = SoupButtonStyle.primary,
    double height = 56,
    FocusNode? focusNode,
    bool expand = false,
    Key? key,
  }) => KeyedSubtree(
    key: key,
    child: AuthButton(
      label: label,
      onPressed: onPressed,
      style: style,
      height: height,
      focusNode: focusNode,
      expand: expand,
    ),
  );
}

/// Web toggle row: title/subtitle with a 52×32 switch (green when on).
class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.focusNode,
    super.key,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) => Focusable(
    focusNode: focusNode,
    onActivate: onChanged == null ? null : () => onChanged!(!value),
    scale: 1.01,
    builder: (context, focused) => Semantics(
      toggled: value,
      label: title,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: focused ? const Color(0x2EFFFFFF) : const Color(0x14FFFFFF),
          borderRadius: BorderRadius.circular(SoupRadii.card),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: SoupType.style(size: 20, weight: 800)),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: SoupType.style(size: 15, color: SoupColors.muted),
                  ),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 52,
              height: 32,
              padding: const EdgeInsets.all(4),
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              decoration: BoxDecoration(
                color: value ? SoupColors.ok : const Color(0xFF3A3A3C),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

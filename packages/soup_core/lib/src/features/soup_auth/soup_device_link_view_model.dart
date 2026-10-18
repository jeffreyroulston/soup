import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:soup_core/src/data/jellyfin/jellyfin_api.dart';
import 'package:soup_core/src/data/session/session_store.dart';
import 'package:soup_core/src/data/soup/soup_session_store.dart';
import 'package:soup_identity/soup_identity.dart';
import 'package:soup_tailscale/soup_tailscale.dart';

enum SoupDeviceLinkPhase {
  idle,
  starting,
  waiting,
  refreshing,
  loadingRoster,
  connectingTransport,
  exchanging,
  ready,
  expired,
  error,

  /// Soup refresh is dead; Google device-link UI required.
  needsGoogleSignIn,
}

/// Soup Identity device-link + Pattern A Jellyfin exchange (Wave 3).
///
/// Flow: device-link → roster (auto-select first server) → optional auth-key
/// Tailscale join → POST /v1/assertions → POST /SoupAuth/Exchange →
/// persist [JellyfinSession]. Cold start restores Soup session and can silently
/// re-exchange when the Jellyfin token fails.
class SoupDeviceLinkViewModel extends ChangeNotifier {
  SoupDeviceLinkViewModel({
    required SoupIdentityClient client,
    required SoupSessionStore sessionStore,
    required SessionStore jellyfinSessionStore,
    required Future<JellyfinApi> Function() jellyfinApiProvider,
    TailscaleClient? tailscaleClient,
    this.connectTransportGrants = true,
    this.performJellyfinExchange = true,
  }) : _client = client,
       _sessionStore = sessionStore,
       _jellyfinSessionStore = jellyfinSessionStore,
       _jellyfinApiProvider = jellyfinApiProvider,
       _tailscaleClient = tailscaleClient;

  final SoupIdentityClient _client;
  final SoupSessionStore _sessionStore;
  final SessionStore _jellyfinSessionStore;
  final Future<JellyfinApi> Function() _jellyfinApiProvider;
  final TailscaleClient? _tailscaleClient;
  final bool connectTransportGrants;
  final bool performJellyfinExchange;

  SoupDeviceLinkPhase _phase = SoupDeviceLinkPhase.idle;
  SoupDeviceLinkPhase get phase => _phase;

  DeviceLinkStart? _link;
  DeviceLinkStart? get link => _link;

  SoupSession? _session;
  SoupSession? get session => _session;

  ServerRoster? _roster;
  ServerRoster? get roster => _roster;

  RosterServer? _selectedServer;
  RosterServer? get selectedServer => _selectedServer;

  JellyfinSession? _jellyfinSession;
  JellyfinSession? get jellyfinSession => _jellyfinSession;

  /// True after a successful auth-key join from a roster transport grant.
  bool _transportConnected = false;
  bool get transportConnected => _transportConnected;

  String? _transportServerId;
  String? get transportServerId => _transportServerId;

  String? _transportError;
  String? get transportError => _transportError;

  String? _exchangeError;
  String? get exchangeError => _exchangeError;

  String? _error;
  String? get error => _error;

  bool _initialized = false;
  bool get initialized => _initialized;

  bool _busy = false;
  bool get isBusy => _busy;

  /// Soup session present and Jellyfin exchange completed (or skipped).
  bool get isFullyReady =>
      _phase == SoupDeviceLinkPhase.ready &&
      _session != null &&
      (!performJellyfinExchange || _jellyfinSession != null);

  /// Show Google QR / progress / exchange retry instead of legacy onboarding.
  bool get showsAuthShell {
    if (_session == null || _phase == SoupDeviceLinkPhase.needsGoogleSignIn) {
      return true;
    }
    switch (_phase) {
      case SoupDeviceLinkPhase.starting:
      case SoupDeviceLinkPhase.waiting:
      case SoupDeviceLinkPhase.loadingRoster:
      case SoupDeviceLinkPhase.connectingTransport:
      case SoupDeviceLinkPhase.exchanging:
      case SoupDeviceLinkPhase.refreshing:
      case SoupDeviceLinkPhase.expired:
      case SoupDeviceLinkPhase.error:
        return true;
      case SoupDeviceLinkPhase.ready:
        return performJellyfinExchange && _jellyfinSession == null;
      case SoupDeviceLinkPhase.idle:
      case SoupDeviceLinkPhase.needsGoogleSignIn:
        return false;
    }
  }

  Timer? _pollTimer;
  int _generation = 0;

  /// When the current device code stops working, from its expires_in.
  DateTime? _linkExpiresAt;

  /// Polls that failed in a row for a reason worth waiting out.
  int _pollFailures = 0;

  /// The refresh in flight, shared by everyone who needs fresh tokens.
  Future<SoupSession>? _refreshing;

  /// Bumped on sign-out, so a refresh that lands afterwards isn't saved.
  int _signOuts = 0;
  bool _disposed = false;
  bool _foreground = true;

  Future<void> initialize() async {
    if (_disposed || _initialized) return;
    _busy = true;
    _notify();
    try {
      final stored = await _readOrDrop(_sessionStore.read, _sessionStore.clear);
      if (_disposed) return;
      _session = stored;
      _jellyfinSession = await _readOrDrop(
        _jellyfinSessionStore.read,
        _jellyfinSessionStore.clear,
      );
      _initialized = true;
      if (stored != null) {
        _phase = SoupDeviceLinkPhase.loadingRoster;
        _notify();
        await _hydrateFromStoredSession(stored);
      }
    } on Object {
      if (!_disposed) {
        _error = 'Could not load your Soup sign-in. Please try again.';
        _initialized = true;
      }
    } finally {
      if (!_disposed) {
        _busy = false;
        _notify();
      }
    }
  }

  /// A stored session that can't be decoded (an older format, a damaged
  /// write) won't fix itself on retry, so it's dropped and sign-in starts
  /// over. Storage errors, which can be transient, still surface.
  static Future<T?> _readOrDrop<T>(
    Future<T?> Function() read,
    Future<void> Function() clear,
  ) async {
    try {
      return await read();
    } on FormatException {
      await clear();
      return null;
    }
  }

  void setForeground(bool foreground) {
    if (_foreground == foreground) return;
    _foreground = foreground;
    if (!foreground) {
      _pollTimer?.cancel();
      _pollTimer = null;
      return;
    }
    if (_phase == SoupDeviceLinkPhase.waiting && _link != null) {
      _schedulePoll(immediate: true);
    }
  }

  Future<void> startDeviceLink({bool newCode = false}) {
    if (_disposed || _busy) return Future.value();
    if (!newCode && _phase == SoupDeviceLinkPhase.waiting && _link != null) {
      return Future.value();
    }
    final generation = ++_generation;
    _busy = true;
    _error = null;
    _exchangeError = null;
    _phase = SoupDeviceLinkPhase.starting;
    _pollTimer?.cancel();
    _pollTimer = null;
    _notify();

    return () async {
      try {
        final start = await _client.startDeviceLink();
        if (_disposed || generation != _generation) return;
        _link = start;
        _linkExpiresAt = DateTime.now().add(Duration(seconds: start.expiresIn));
        _pollFailures = 0;
        _phase = SoupDeviceLinkPhase.waiting;
        _busy = false;
        _notify();
        _schedulePoll(immediate: true);
      } on Object catch (error) {
        if (_disposed || generation != _generation) return;
        _phase = SoupDeviceLinkPhase.error;
        _error = _friendlyError(error);
        _busy = false;
        _notify();
      }
    }();
  }

  void _schedulePoll({bool immediate = false}) {
    _pollTimer?.cancel();
    final link = _link;
    if (link == null || !_foreground) return;
    if (_linkExpired) {
      _expireLink();
      return;
    }
    // Back off while polls fail (offline, server busy, rate limited).
    final interval = link.interval.clamp(1, 60);
    final backoff = interval * (1 << _pollFailures.clamp(0, 4));
    final delay = immediate
        ? Duration.zero
        : Duration(seconds: backoff.clamp(interval, 60));
    _pollTimer = Timer(delay, () => unawaited(_poll(link.deviceCode)));
  }

  bool get _linkExpired {
    final expiresAt = _linkExpiresAt;
    return expiresAt != null && DateTime.now().isAfter(expiresAt);
  }

  /// Ends the wait once the code's lifetime is up, without needing the
  /// server to say so: polls that keep failing never would.
  void _expireLink() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _phase = SoupDeviceLinkPhase.expired;
    _error = 'This code has expired. Get a new code to continue.';
    _notify();
  }

  /// Network trouble, timeouts, server errors and rate limiting pass; the
  /// approval may still come through, so polling carries on.
  static bool _isTransient(SoupIdentityException error) {
    final status = error.statusCode;
    return status == null || status == 429 || status >= 500;
  }

  Future<void> _poll(String deviceCode) async {
    if (_disposed || !_foreground || _phase != SoupDeviceLinkPhase.waiting) {
      return;
    }
    final generation = _generation;
    try {
      final poll = await _client.pollDeviceLink(deviceCode);
      if (_disposed || generation != _generation) return;
      _pollFailures = 0;
      switch (poll.status) {
        case DeviceLinkStatus.pending:
          _schedulePoll();
        case DeviceLinkStatus.expired:
          _phase = SoupDeviceLinkPhase.expired;
          _error = 'This code has expired. Get a new code to continue.';
          _notify();
        case DeviceLinkStatus.approved:
          final tokens = poll.tokens;
          if (tokens == null) {
            _phase = SoupDeviceLinkPhase.error;
            _error = 'Soup approved the device but returned no tokens.';
            _notify();
            return;
          }
          await _complete(tokens, generation);
      }
    } on SoupIdentityException catch (error) {
      if (_disposed || generation != _generation) return;
      if (error.statusCode == 404) {
        _phase = SoupDeviceLinkPhase.expired;
        _error = 'This code is no longer valid. Get a new code to continue.';
      } else if (_isTransient(error)) {
        _pollFailures++;
        _schedulePoll(); // or expires the code, once its time is up
        return;
      } else {
        _phase = SoupDeviceLinkPhase.error;
        _error = _friendlyError(error);
      }
      _notify();
    } on Object catch (error) {
      if (_disposed || generation != _generation) return;
      _phase = SoupDeviceLinkPhase.error;
      _error = _friendlyError(error);
      _notify();
    }
  }

  Future<void> _complete(SoupSessionTokens tokens, int generation) async {
    _busy = true;
    _phase = SoupDeviceLinkPhase.loadingRoster;
    _notify();
    try {
      var session = SoupSession.fromTokens(tokens);
      ServerRoster? roster;
      try {
        roster = await _client.listServers(tokens.accessToken);
        final selected = roster.autoSelected;
        if (selected != null) {
          session = session.copyWith(lastServerId: selected.id);
        }
      } on Object {
        roster = null;
      }
      if (_disposed || generation != _generation) return;
      await _sessionStore.write(session);
      if (_disposed || generation != _generation) return;
      _session = session;
      _roster = roster;
      _selectedServer = _resolveSelected(roster, session.lastServerId);
      await _maybeConnectTransport(roster, generation);
      if (_disposed || generation != _generation) return;
      await _maybeExchange(session, generation);
      if (_disposed || generation != _generation) return;
      if (_phase != SoupDeviceLinkPhase.error &&
          _phase != SoupDeviceLinkPhase.needsGoogleSignIn) {
        _phase = SoupDeviceLinkPhase.ready;
      }
    } on Object catch (error) {
      if (_disposed || generation != _generation) return;
      _phase = SoupDeviceLinkPhase.error;
      _error = _friendlyError(error);
    } finally {
      if (!_disposed && generation == _generation) {
        _busy = false;
        _notify();
      }
    }
  }

  /// [fromStartup] lets cold-start hydration refresh an expired access token
  /// while [initialize] still holds the busy flag; without it the refresh was
  /// silently skipped and the sign-in screen waited on "Loading your servers"
  /// forever.
  Future<void> refreshAndReloadRoster({bool fromStartup = false}) async {
    final session = _session;
    if (_disposed || session == null || (_busy && !fromStartup)) return;
    final generation = ++_generation;
    _busy = true;
    _phase = SoupDeviceLinkPhase.refreshing;
    _error = null;
    _notify();
    try {
      var next = await _refreshTokens(session);
      if (_disposed || generation != _generation) return;
      final roster = await _client.listServers(next.accessToken);
      if (_disposed || generation != _generation) return;
      final selected = roster.autoSelected;
      if (selected != null && next.lastServerId == null) {
        next = next.copyWith(lastServerId: selected.id);
        await _sessionStore.write(next);
        if (_disposed || generation != _generation) return;
      }
      _session = next;
      _roster = roster;
      _selectedServer = _resolveSelected(roster, next.lastServerId);
      await _maybeConnectTransport(roster, generation);
      if (_disposed || generation != _generation) return;
      await _maybeExchange(next, generation);
      if (_disposed || generation != _generation) return;
      if (_phase != SoupDeviceLinkPhase.error &&
          _phase != SoupDeviceLinkPhase.needsGoogleSignIn) {
        _phase = SoupDeviceLinkPhase.ready;
      }
    } on SoupIdentityException catch (error) {
      if (_disposed || generation != _generation) return;
      if (error.statusCode == 401) {
        await _forceGoogleSignIn();
      } else {
        _phase = SoupDeviceLinkPhase.error;
        _error = _friendlyError(error);
      }
    } on Object catch (error) {
      if (_disposed || generation != _generation) return;
      _phase = SoupDeviceLinkPhase.error;
      _error = _friendlyError(error);
    } finally {
      if (!_disposed && generation == _generation) {
        _busy = false;
        _notify();
      }
    }
  }

  /// Silent re-exchange when a stored Jellyfin token fails (401).
  ///
  /// Refreshes Soup access if needed, mints a new assertion, exchanges, and
  /// replaces the Jellyfin session. Returns false when Google UI is required.
  Future<bool> silentReExchange() async {
    if (_disposed || !performJellyfinExchange) return false;
    var session = _session;
    if (session == null) {
      await _forceGoogleSignIn();
      return false;
    }
    final generation = ++_generation;
    _busy = true;
    _phase = SoupDeviceLinkPhase.exchanging;
    _exchangeError = null;
    _error = null;
    _notify();
    try {
      if (_expiresSoon(session)) {
        session = await _refreshTokens(session);
        if (_disposed || generation != _generation) return false;
      }
      try {
        await _ensureRoster(session, generation);
      } on SoupIdentityException catch (error) {
        if (error.statusCode == 401) {
          session = await _refreshTokens(session);
          if (_disposed || generation != _generation) return false;
          await _ensureRoster(session, generation);
        } else {
          rethrow;
        }
      }
      if (_disposed || generation != _generation) return false;
      await _maybeConnectTransport(_roster, generation);
      if (_disposed || generation != _generation) return false;
      final exchanged = await _exchangeNow(session, generation);
      if (_disposed || generation != _generation) return false;
      if (!exchanged) {
        _phase = SoupDeviceLinkPhase.error;
        return false;
      }
      _phase = SoupDeviceLinkPhase.ready;
      return true;
    } on SoupIdentityException catch (error) {
      if (_disposed || generation != _generation) return false;
      if (error.statusCode == 401) {
        await _forceGoogleSignIn();
        return false;
      }
      _phase = SoupDeviceLinkPhase.error;
      _error = _friendlyError(error);
      return false;
    } on Object catch (error) {
      if (_disposed || generation != _generation) return false;
      _phase = SoupDeviceLinkPhase.error;
      _error = _friendlyError(error);
      return false;
    } finally {
      if (!_disposed && generation == _generation) {
        _busy = false;
        _notify();
      }
    }
  }

  String? _switchingServerId;

  /// Roster server [selectServer] is exchanging with, for a spinner.
  String? get switchingServerId => _switchingServerId;

  /// Signs in to another roster server and remembers it for next launch.
  ///
  /// Leaves [phase] at ready throughout, so [showsAuthShell] doesn't swap the
  /// app back to sign-in mid-switch. Returns null on success; on failure the
  /// previous server and Jellyfin session stay in place and the error is
  /// returned.
  Future<String?> selectServer(String serverId) async {
    var session = _session;
    final roster = _roster;
    if (_disposed ||
        _busy ||
        !performJellyfinExchange ||
        session == null ||
        roster == null ||
        serverId == _selectedServer?.id) {
      return null;
    }
    RosterServer? target;
    for (final server in roster.servers) {
      if (server.id == serverId) target = server;
    }
    if (target == null) return 'That server is no longer on your Soup roster.';

    final generation = ++_generation;
    final previousServer = _selectedServer;
    _busy = true;
    _switchingServerId = serverId;
    _selectedServer = target;
    _notify();
    try {
      bool exchanged;
      try {
        exchanged = await _exchangeNow(session, generation);
      } on SoupIdentityException catch (error) {
        if (error.statusCode != 401) rethrow;
        session = await _refreshTokens(session);
        if (_disposed || generation != _generation) return null;
        exchanged = await _exchangeNow(session, generation);
      }
      if (_disposed || generation != _generation) return null;
      if (!exchanged) {
        final message = _exchangeError ?? 'Could not switch servers.';
        _exchangeError = null;
        _selectedServer = previousServer;
        _phase = SoupDeviceLinkPhase.ready;
        return message;
      }
      // _session may hold tokens refreshed since this switch began.
      final next = (_session ?? session).copyWith(lastServerId: target.id);
      await _sessionStore.write(next);
      if (_disposed || generation != _generation) return null;
      _session = next;
      return null;
    } on SoupIdentityException catch (error) {
      if (_disposed || generation != _generation) return null;
      if (error.statusCode == 401) {
        await _forceGoogleSignIn();
        return 'Your Soup sign-in expired. Sign in with Google again.';
      }
      _selectedServer = previousServer;
      return _friendlyError(error);
    } on Object catch (error) {
      if (_disposed || generation != _generation) return null;
      _selectedServer = previousServer;
      return _friendlyError(error);
    } finally {
      if (_switchingServerId == serverId) _switchingServerId = null;
      if (!_disposed && generation == _generation) {
        _busy = false;
        _notify();
      }
    }
  }

  /// Probe stored Jellyfin session; silent re-exchange on 401.
  Future<bool> ensureJellyfinSessionValid() async {
    if (_disposed || !performJellyfinExchange) return true;
    final existing = _jellyfinSession ?? await _jellyfinSessionStore.read();
    if (existing == null) {
      return silentReExchange();
    }
    _jellyfinSession = existing;
    try {
      final api = await _jellyfinApiProvider();
      await api.validateSession(existing);
      return true;
    } on JellyfinApiException catch (error) {
      if (error.statusCode == 401) {
        return silentReExchange();
      }
      rethrow;
    }
  }

  Future<void> clearSession() async {
    _generation++;
    _signOuts++;
    if (_session?.refreshToken case final refreshToken?) {
      // Best effort and not awaited, like the Jellyfin logout.
      unawaited(_client.revokeSession(refreshToken).catchError((Object _) {}));
    }
    _pollTimer?.cancel();
    _pollTimer = null;
    await _sessionStore.clear();
    await _jellyfinSessionStore.clear();
    if (_disposed) return;
    _session = null;
    _jellyfinSession = null;
    _roster = null;
    _selectedServer = null;
    _link = null;
    _transportConnected = false;
    _transportServerId = null;
    _transportError = null;
    _exchangeError = null;
    _error = null;
    _phase = SoupDeviceLinkPhase.idle;
    _notify();
  }

  Future<void> _hydrateFromStoredSession(SoupSession session) async {
    if (_expiresSoon(session)) {
      // Skip the roster call that would only come back 401.
      await refreshAndReloadRoster(fromStartup: true);
      return;
    }
    final generation = _generation;
    try {
      await _ensureRoster(session, generation);
      if (_disposed || generation != _generation) return;
      await _maybeConnectTransport(_roster, generation);
      if (_disposed || generation != _generation) return;
      if (performJellyfinExchange) {
        final existing = _jellyfinSession ?? await _jellyfinSessionStore.read();
        if (existing != null) {
          _jellyfinSession = existing;
          try {
            final api = await _jellyfinApiProvider();
            await api.validateSession(existing);
          } on JellyfinApiException catch (error) {
            if (error.statusCode == 401) {
              final ok = await silentReExchange();
              if (!ok) return;
            } else {
              // Keep stored session; library load can retry.
            }
          }
        } else {
          await _maybeExchange(session, generation);
        }
      }
      if (_disposed || generation != _generation) return;
      if (_phase != SoupDeviceLinkPhase.error &&
          _phase != SoupDeviceLinkPhase.needsGoogleSignIn) {
        _phase = SoupDeviceLinkPhase.ready;
      }
      _notify();
    } on SoupIdentityException catch (error) {
      if (error.statusCode == 401) {
        try {
          await refreshAndReloadRoster(fromStartup: true);
        } on Object {
          await _forceGoogleSignIn();
        }
      } else if (!_disposed) {
        _phase = SoupDeviceLinkPhase.ready;
        _notify();
      }
    } on Object {
      if (!_disposed) {
        _phase = SoupDeviceLinkPhase.ready;
        _notify();
      }
    }
  }

  Future<void> _ensureRoster(SoupSession session, int generation) async {
    final roster = await _client.listServers(session.accessToken);
    if (_disposed || generation != _generation) return;
    _roster = roster;
    _selectedServer = _resolveSelected(roster, session.lastServerId);
    if (_selectedServer != null &&
        session.lastServerId != _selectedServer!.id) {
      final next = (_session ?? session).copyWith(
        lastServerId: _selectedServer!.id,
      );
      await _sessionStore.write(next);
      if (_disposed || generation != _generation) return;
      _session = next;
    }
  }

  /// New tokens for [stale], from one refresh shared by every caller.
  ///
  /// Soup Identity rotates refresh tokens: a second refresh with the same
  /// token gets a 401 and signs the device out. So concurrent callers share
  /// the request, a caller holding tokens someone else already refreshed gets
  /// those, and the result is saved before anything else can fail or be
  /// cancelled, since the old refresh token is dead either way.
  Future<SoupSession> _refreshTokens(SoupSession stale) {
    final current = _session;
    if (current != null && current.accessToken != stale.accessToken) {
      return Future.value(current);
    }
    return _refreshing ??= () async {
      try {
        final base = current ?? stale;
        final signOuts = _signOuts;
        final tokens = await _client.refreshSession(base.refreshToken);
        final latest = _session ?? base;
        final next =
            SoupSession.fromTokens(
              tokens,
              lastServerId: latest.lastServerId,
            ).copyWith(
              pendingTransportKey: latest.pendingTransportKey,
              pendingTransportServerId: latest.pendingTransportServerId,
            );
        if (signOuts == _signOuts) {
          await _sessionStore.write(next);
          if (!_disposed && signOuts == _signOuts) _session = next;
        }
        return next;
      } finally {
        _refreshing = null;
      }
    }();
  }

  /// Saves [change] applied to the current session, if there is one.
  Future<void> _updateSession(SoupSession Function(SoupSession) change) async {
    final current = _session;
    if (current == null) return;
    final next = change(current);
    await _sessionStore.write(next);
    if (!_disposed) _session = next;
  }

  /// Whether [session]'s access token is expired or about to be, so it's
  /// worth refreshing before use rather than waiting for a 401.
  static bool _expiresSoon(SoupSession session) {
    final expiresAt = session.accessExpiresAt;
    if (expiresAt == null) return false;
    return DateTime.now().toUtc().isAfter(
      expiresAt.subtract(const Duration(minutes: 1)),
    );
  }

  RosterServer? _resolveSelected(ServerRoster? roster, String? lastServerId) {
    if (roster == null || roster.servers.isEmpty) return null;
    if (lastServerId != null) {
      for (final server in roster.servers) {
        if (server.id == lastServerId) return server;
      }
    }
    return roster.autoSelected;
  }

  /// Claimable grant → [connectWithAuthKey] → wait connected.
  ///
  /// The roster includes a grant's key only once, so it's saved before the
  /// join and cleared only after it works; a failed join retries with the
  /// saved key next time.
  Future<void> _maybeConnectTransport(
    ServerRoster? roster,
    int generation,
  ) async {
    final client = _tailscaleClient;
    if (!connectTransportGrants || client == null || roster == null) {
      return;
    }
    if (_transportConnected &&
        client.status.phase == TailscaleConnectionPhase.connected) {
      return;
    }
    final claimable = RosterServer.firstClaimableAuthKey(roster.servers);
    final String material;
    final String? serverId;
    if (claimable != null) {
      material = claimable.grant.material!.trim();
      serverId = claimable.server.id;
      await _updateSession(
        (s) => s.copyWith(
          pendingTransportKey: material,
          pendingTransportServerId: serverId,
        ),
      );
      if (_disposed || generation != _generation) return;
    } else if (_session?.pendingTransportKey case final saved?) {
      material = saved;
      serverId = _session?.pendingTransportServerId;
    } else {
      return;
    }

    _phase = SoupDeviceLinkPhase.connectingTransport;
    _transportError = null;
    _notify();
    try {
      await client.connectWithAuthKey(authKey: material);
      if (_disposed || generation != _generation) return;
      await client.waitUntilConnected(timeout: const Duration(seconds: 30));
      if (_disposed || generation != _generation) return;
      await _updateSession((s) => s.copyWith(clearPendingTransport: true));
      if (_disposed || generation != _generation) return;
      _transportConnected = true;
      _transportServerId = serverId;
      _transportError = null;
    } on Object catch (error) {
      if (_disposed || generation != _generation) return;
      _transportConnected = false;
      _transportServerId = null;
      _transportError =
          'Could not join Tailscale with the Soup transport grant. ${_friendlyError(error)}';
    }
  }

  Future<void> _maybeExchange(SoupSession session, int generation) async {
    if (!performJellyfinExchange) return;
    if (_jellyfinSession != null) return;
    _phase = SoupDeviceLinkPhase.exchanging;
    _exchangeError = null;
    _notify();
    await _exchangeNow(session, generation);
  }

  Future<bool> _exchangeNow(SoupSession session, int generation) async {
    final server = _selectedServer ?? _roster?.autoSelected;
    if (server == null) {
      _exchangeError =
          'No Soup servers yet. Ask the host to invite this Google account.';
      _phase = SoupDeviceLinkPhase.error;
      return false;
    }
    final serverUrl = server.jellyfinServerUrl;
    if (serverUrl == null ||
        !{'http', 'https'}.contains(serverUrl.scheme) ||
        serverUrl.host.isEmpty) {
      _exchangeError =
          'This Soup server has no reachable Jellyfin address yet.';
      _phase = SoupDeviceLinkPhase.error;
      return false;
    }
    try {
      final minted = await _client.mintAssertion(
        accessToken: session.accessToken,
        serverId: server.id,
      );
      if (_disposed || generation != _generation) return false;
      final api = await _jellyfinApiProvider();
      if (_disposed || generation != _generation) return false;
      final jellyfin = await api.exchangeSoupAuth(
        serverUrl: JellyfinApi.parseServerUrl(serverUrl.toString()),
        assertion: minted.assertion,
      );
      if (_disposed || generation != _generation) return false;
      await _jellyfinSessionStore.write(jellyfin);
      if (_disposed || generation != _generation) return false;
      _jellyfinSession = jellyfin;
      _selectedServer = server;
      _exchangeError = null;
      return true;
    } on SoupIdentityException catch (error) {
      if (error.statusCode == 401) rethrow;
      _exchangeError = _friendlyError(error);
      _phase = SoupDeviceLinkPhase.error;
      return false;
    } on Object catch (error) {
      _exchangeError = _friendlyError(error);
      _phase = SoupDeviceLinkPhase.error;
      return false;
    }
  }

  Future<void> _forceGoogleSignIn() async {
    _signOuts++;
    await _sessionStore.clear();
    await _jellyfinSessionStore.clear();
    if (_disposed) return;
    _session = null;
    _jellyfinSession = null;
    _roster = null;
    _selectedServer = null;
    _link = null;
    _transportConnected = false;
    _transportServerId = null;
    _transportError = null;
    _exchangeError = null;
    _error = 'Your Soup sign-in expired. Sign in with Google again.';
    _phase = SoupDeviceLinkPhase.needsGoogleSignIn;
    _notify();
  }

  String _friendlyError(Object error) {
    if (error is SoupIdentityException) {
      final detail = error.statusCode == null
          ? error.message
          : '${error.message} (HTTP ${error.statusCode})';
      return 'Soup Identity error: ${redactSecrets(detail)}';
    }
    if (error is TailscaleException) {
      return redactSecrets(error.message);
    }
    if (error is JellyfinApiException) {
      return redactSecrets(error.message);
    }
    final raw = error.toString();
    // The raw error (URLs, errno) is for the log, not the screen.
    debugPrint('[soup] sign-in error: ${redactSecrets(raw)}');
    if (raw.contains('SocketException') ||
        raw.contains('ClientException') ||
        raw.contains('Failed host lookup') ||
        raw.contains('Connection refused') ||
        raw.contains('Connection reset') ||
        raw.contains('timed out') ||
        raw.contains('TimeoutException')) {
      // The Jellyfin exchange goes to the media server; the rest of sign-in
      // to Soup Identity. Name whichever one didn't answer.
      final server = _selectedServer;
      final base = Uri.tryParse(server?.baseUrl ?? '');
      final toServer =
          raw.contains('/SoupAuth/') ||
          (base != null && base.host.isNotEmpty && raw.contains(base.host));
      if (toServer) {
        final name = server?.name ?? 'your server';
        return "Can't reach $name. Make sure it's turned on and connected "
            'to your network, then try again.';
      }
      return "Can't reach Soup's sign-in service. Check your internet "
          'connection, then try again.';
    }
    return 'Something went wrong signing in. Try again in a moment.';
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    _client.close();
    super.dispose();
  }
}

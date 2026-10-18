import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:soup_core/src/data/jellyfin/jellyfin_api.dart';
import 'package:soup_core/src/data/soup/soup_session_store.dart';
import 'package:soup_core/src/features/soup_auth/soup_device_link_view_model.dart';
import 'package:soup_identity/soup_identity.dart';
import 'package:soup_tailscale/soup_tailscale.dart';

import 'support/connectivity_fakes.dart';

void main() {
  SoupDeviceLinkViewModel buildModel({
    required SoupIdentityClient client,
    SoupSessionStore? soupStore,
    MemorySessionStore? jellyfinStore,
    TailscaleClient? tailscale,
    bool connectTransportGrants = true,
    bool performJellyfinExchange = true,
    Future<JellyfinApi> Function()? jellyfinApiProvider,
  }) {
    final jfStore = jellyfinStore ?? MemorySessionStore();
    return SoupDeviceLinkViewModel(
      client: client,
      sessionStore: soupStore ?? MemorySoupSessionStore(),
      jellyfinSessionStore: jfStore,
      jellyfinApiProvider:
          jellyfinApiProvider ??
          () async => JellyfinApi(
            MockClient((request) async {
              if (request.url.path.endsWith('/SoupAuth/Exchange')) {
                return http.Response(
                  '{"AccessToken":"soup-token","ServerId":"jf-1","User":{"Id":"u1","Name":"Guest"}}',
                  200,
                );
              }
              if (request.url.path.contains('/Users/')) {
                return http.Response('{"Id":"u1","Name":"Guest"}', 200);
              }
              return http.Response('{}', 404);
            }),
            deviceId: 'soup-device',
          ),
      tailscaleClient: tailscale,
      connectTransportGrants: connectTransportGrants,
      performJellyfinExchange: performJellyfinExchange,
    );
  }

  test(
    'device-link poll stores session, auto-selects server, exchanges',
    () async {
      final client = MockSoupIdentityClient(pollsUntilApproved: 1);
      final soupStore = MemorySoupSessionStore();
      final jellyfinStore = MemorySessionStore();
      final model = buildModel(
        client: client,
        soupStore: soupStore,
        jellyfinStore: jellyfinStore,
        performJellyfinExchange: true,
      );
      addTearDown(model.dispose);

      await model.initialize();
      expect(model.session, isNull);

      await model.startDeviceLink();
      await pumpUntil(
        () => model.phase == SoupDeviceLinkPhase.ready,
        timeout: const Duration(seconds: 2),
      );

      expect(model.session?.accessToken, 'mock-access');
      expect(model.session?.lastServerId, 'home-jf');
      expect(soupStore.session?.refreshToken, 'mock-refresh');
      expect(model.roster?.servers.single.id, 'home-jf');
      expect(model.selectedServer?.id, 'home-jf');
      expect(model.jellyfinSession?.accessToken, 'soup-token');
      expect(jellyfinStore.session?.accessToken, 'soup-token');
      expect(model.transportConnected, isFalse);
    },
  );

  test(
    'roster transport grant calls connectWithAuthKey then exchanges',
    () async {
      final grant = TransportGrant(
        id: '11111111-1111-1111-1111-111111111111',
        grantType: 'tailscale_auth_key',
        expiresAt: DateTime.utc(2026, 9, 10, 12),
        material: 'tskey-auth-wave2c',
      );
      final client = MockSoupIdentityClient(
        pollsUntilApproved: 1,
        servers: [
          RosterServer(
            id: 'home-jf',
            name: 'Home',
            audience: 'jellyfin:home-jf',
            magicDns: 'jellyfin.tailnet.ts.net',
            transportGrant: grant,
          ),
        ],
      );
      final tailscale = FakeTailscaleClient();
      addTearDown(tailscale.dispose);
      final model = buildModel(
        client: client,
        tailscale: tailscale,
        connectTransportGrants: true,
      );
      addTearDown(model.dispose);

      await model.initialize();
      await model.startDeviceLink();
      await pumpUntil(
        () => model.phase == SoupDeviceLinkPhase.ready,
        timeout: const Duration(seconds: 2),
      );

      expect(tailscale.authKeyConnects, 1);
      expect(tailscale.lastAuthKey, 'tskey-auth-wave2c');
      expect(model.transportConnected, isTrue);
      expect(model.transportServerId, 'home-jf');
      expect(model.transportError, isNull);
      expect(model.jellyfinSession?.accessToken, 'soup-token');
    },
  );

  test('a failed grant join retries later with the saved key', () async {
    final server = RosterServer(
      id: 'home-jf',
      name: 'Home',
      audience: 'jellyfin:home-jf',
      magicDns: 'jellyfin.tailnet.ts.net',
      transportGrant: TransportGrant(
        id: '11111111-1111-1111-1111-111111111111',
        grantType: 'tailscale_auth_key',
        expiresAt: DateTime.utc(2026, 9, 10, 12),
        material: 'tskey-auth-once',
      ),
    );
    final client = OneShotGrantClient(
      MockSoupIdentityClient(pollsUntilApproved: 1, servers: [server]),
    );
    final tailscale = FakeTailscaleClient()
      ..connectError = const TailscaleException('tailscale_start', 'offline');
    addTearDown(tailscale.dispose);
    final store = MemorySoupSessionStore();
    final model = buildModel(
      client: client,
      soupStore: store,
      tailscale: tailscale,
    );
    addTearDown(model.dispose);

    await model.initialize();
    await model.startDeviceLink();
    await pumpUntil(() => !model.isBusy && model.session != null);

    expect(model.transportConnected, isFalse);
    expect(store.session?.pendingTransportKey, 'tskey-auth-once');

    tailscale.connectError = null;
    await model.refreshAndReloadRoster();

    expect(client.rosterCalls, greaterThan(1));
    expect(tailscale.authKeyConnects, 2);
    expect(tailscale.lastAuthKey, 'tskey-auth-once');
    expect(model.transportConnected, isTrue);
    expect(model.transportServerId, 'home-jf');
    expect(store.session?.pendingTransportKey, isNull);
  });

  test('transport grant connect is skipped when feature flag is off', () async {
    final client = MockSoupIdentityClient(
      pollsUntilApproved: 1,
      servers: [
        RosterServer(
          id: 'home-jf',
          name: 'Home',
          audience: 'jellyfin:home-jf',
          magicDns: 'jellyfin.tailnet.ts.net',
          transportGrant: TransportGrant(
            id: '11111111-1111-1111-1111-111111111111',
            grantType: 'tailscale_auth_key',
            expiresAt: DateTime.utc(2026, 9, 10, 12),
            material: 'tskey-auth-skipped',
          ),
        ),
      ],
    );
    final tailscale = FakeTailscaleClient();
    addTearDown(tailscale.dispose);
    final model = buildModel(
      client: client,
      tailscale: tailscale,
      connectTransportGrants: false,
    );
    addTearDown(model.dispose);

    await model.initialize();
    await model.startDeviceLink();
    await pumpUntil(
      () => model.phase == SoupDeviceLinkPhase.ready,
      timeout: const Duration(seconds: 2),
    );

    expect(tailscale.authKeyConnects, 0);
    expect(model.transportConnected, isFalse);
    expect(model.jellyfinSession?.accessToken, 'soup-token');
  });

  test('refresh rotates tokens through the client', () async {
    final client = MockSoupIdentityClient(pollsUntilApproved: 1);
    final store = MemorySoupSessionStore(
      SoupSession.fromTokens(
        const SoupSessionTokens(
          accessToken: 'mock-access',
          refreshToken: 'mock-refresh',
          expiresIn: 900,
          tokenType: 'Bearer',
          email: 'dev@example.com',
        ),
        lastServerId: 'home-jf',
      ),
    );
    final model = buildModel(client: client, soupStore: store);
    addTearDown(model.dispose);

    await model.initialize();
    await model.refreshAndReloadRoster();
    expect(model.phase, SoupDeviceLinkPhase.ready);
    expect(model.session?.accessToken, startsWith('mock-access-'));
    expect(model.session?.refreshToken, startsWith('mock-refresh-'));
    expect(store.session?.lastServerId, 'home-jf');
  });

  test('silent re-exchange replaces expired Jellyfin token', () async {
    final client = MockSoupIdentityClient();
    final soupStore = MemorySoupSessionStore(
      SoupSession.fromTokens(
        const SoupSessionTokens(
          accessToken: 'mock-access',
          refreshToken: 'mock-refresh',
          expiresIn: 900,
          tokenType: 'Bearer',
          email: 'dev@example.com',
        ),
        lastServerId: 'home-jf',
      ),
    );
    final jellyfinStore = MemorySessionStore(
      JellyfinSession(
        serverUrl: Uri.parse('http://jellyfin.tailnet.ts.net/'),
        serverId: 'old',
        userId: 'u1',
        userName: 'Guest',
        accessToken: 'expired',
      ),
    );
    var probes = 0;
    final model = buildModel(
      client: client,
      soupStore: soupStore,
      jellyfinStore: jellyfinStore,
      jellyfinApiProvider: () async => JellyfinApi(
        MockClient((request) async {
          if (request.url.path.endsWith('/SoupAuth/Exchange')) {
            return http.Response(
              '{"AccessToken":"fresh-token","ServerId":"jf-1","User":{"Id":"u1","Name":"Guest"}}',
              200,
            );
          }
          if (request.url.path.contains('/Users/')) {
            probes++;
            if (probes == 1) {
              return http.Response('Unauthorized', 401);
            }
            return http.Response('{"Id":"u1","Name":"Guest"}', 200);
          }
          return http.Response('{}', 404);
        }),
        deviceId: 'soup-device',
      ),
    );
    addTearDown(model.dispose);

    await model.initialize();
    expect(model.jellyfinSession?.accessToken, 'fresh-token');
    expect(jellyfinStore.session?.accessToken, 'fresh-token');
    expect(model.phase, SoupDeviceLinkPhase.ready);
  });
  test(
    'cold start with an expired access token refreshes instead of hanging',
    () async {
      final inner = MockSoupIdentityClient();
      final client = ExpiredFirstClient(inner);
      final store = MemorySoupSessionStore(
        SoupSession.fromTokens(
          const SoupSessionTokens(
            accessToken: 'stale-access',
            refreshToken: 'mock-refresh',
            expiresIn: 900,
            tokenType: 'Bearer',
            email: 'dev@example.com',
          ),
          lastServerId: 'home-jf',
        ),
      );
      final model = buildModel(
        client: client,
        soupStore: store,
        performJellyfinExchange: false,
      );
      addTearDown(model.dispose);

      await model.initialize();

      expect(client.rejectedStaleToken, isTrue);
      expect(model.phase, SoupDeviceLinkPhase.ready);
      expect(model.session?.accessToken, startsWith('mock-access-'));
      expect(store.session?.accessToken, startsWith('mock-access-'));
    },
  );

  group('token refresh', () {
    SoupSession stored({DateTime? issuedAt}) => SoupSession.fromTokens(
      const SoupSessionTokens(
        accessToken: 'stale-access',
        refreshToken: 'refresh-0',
        expiresIn: 900,
        tokenType: 'Bearer',
        email: 'dev@example.com',
      ),
      lastServerId: 'home-jf',
      issuedAt: issuedAt,
    );

    test(
      'concurrent refreshes share one request and keep the session',
      () async {
        final client = RotatingClient(MockSoupIdentityClient());
        final store = MemorySoupSessionStore(stored());
        final model = buildModel(
          client: client,
          soupStore: store,
          jellyfinStore: MemorySessionStore(),
        );
        addTearDown(model.dispose);
        await model.initialize();
        client.refreshes = 0;
        client.rejectAccess.add(model.session!.accessToken);

        final gate = client.holdRefresh();
        final a = model.refreshAndReloadRoster(fromStartup: true);
        final b = model.silentReExchange();
        await pumpUntil(() => client.refreshes == 1);
        gate.complete();
        await Future.wait([a, b]);

        expect(client.refreshes, 1);
        expect(model.phase, isNot(SoupDeviceLinkPhase.needsGoogleSignIn));
        expect(store.session?.refreshToken, client.validRefresh);
      },
    );

    test('a roster failure after refresh still saves the new tokens', () async {
      final client = RotatingClient(MockSoupIdentityClient());
      final store = MemorySoupSessionStore(stored());
      final model = buildModel(client: client, soupStore: store);
      addTearDown(model.dispose);
      await model.initialize();

      client.failRoster = true;
      await model.refreshAndReloadRoster();

      expect(model.phase, SoupDeviceLinkPhase.error);
      expect(store.session?.refreshToken, client.validRefresh);
      expect(store.session?.refreshToken, isNot('refresh-0'));
      expect(store.session?.lastServerId, 'home-jf');
    });

    test(
      'an expired access token is refreshed before startup uses it',
      () async {
        final client = RotatingClient(MockSoupIdentityClient());
        final store = MemorySoupSessionStore(
          stored(
            issuedAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
          ),
        );
        client.rejectAccess.add('stale-access');
        final model = buildModel(
          client: client,
          soupStore: store,
          performJellyfinExchange: false,
        );
        addTearDown(model.dispose);

        await model.initialize();

        expect(client.refreshes, 1);
        expect(client.rosterTokens, isNot(contains('stale-access')));
        expect(model.phase, SoupDeviceLinkPhase.ready);
      },
    );

    test('a refresh that lands after sign-out is not saved', () async {
      final client = RotatingClient(MockSoupIdentityClient());
      final store = MemorySoupSessionStore(stored());
      final model = buildModel(client: client, soupStore: store);
      addTearDown(model.dispose);
      await model.initialize();

      final gate = client.holdRefresh();
      final refresh = model.refreshAndReloadRoster();
      await pumpUntil(() => client.refreshes == 1);
      await model.clearSession();
      gate.complete();
      await refresh;

      expect(store.session, isNull);
      expect(model.session, isNull);
    });
  });

  test('sign-out revokes the Soup refresh token', () async {
    final inner = MockSoupIdentityClient();
    final store = MemorySoupSessionStore(
      SoupSession.fromTokens(
        const SoupSessionTokens(
          accessToken: 'mock-access',
          refreshToken: 'mock-refresh',
          expiresIn: 900,
          tokenType: 'Bearer',
          email: 'dev@example.com',
        ),
      ),
    );
    final model = buildModel(
      client: inner,
      soupStore: store,
      performJellyfinExchange: false,
    );
    addTearDown(model.dispose);
    await model.initialize();

    await model.clearSession();
    await Future<void>.delayed(Duration.zero);

    expect(inner.revoked, ['mock-refresh']);
    expect(store.session, isNull);
  });

  group('selectServer', () {
    const servers = [
      RosterServer(
        id: 'home-jf',
        name: 'Home',
        audience: 'jellyfin:home-jf',
        magicDns: 'home.tailnet.ts.net',
      ),
      RosterServer(
        id: 'test-jf',
        name: 'Test',
        audience: 'jellyfin:test-jf',
        magicDns: 'test.tailnet.ts.net',
      ),
    ];

    /// Exchanges per host; [down] hosts fail with a 500.
    Future<JellyfinApi> perHostApi({
      Set<String> down = const {},
    }) async => JellyfinApi(
      MockClient((request) async {
        final host = request.url.host;
        if (down.contains(host)) return http.Response('down', 500);
        if (request.url.path.endsWith('/SoupAuth/Exchange')) {
          return http.Response(
            '{"AccessToken":"token-$host","ServerId":"jf-$host","User":{"Id":"u1","Name":"Guest"}}',
            200,
          );
        }
        return http.Response('{}', 404);
      }),
      deviceId: 'soup-device',
    );

    Future<SoupDeviceLinkViewModel> readyModel({
      required MemorySoupSessionStore soupStore,
      required MemorySessionStore jellyfinStore,
      Set<String> down = const {},
    }) async {
      final model = buildModel(
        client: MockSoupIdentityClient(pollsUntilApproved: 1, servers: servers),
        soupStore: soupStore,
        jellyfinStore: jellyfinStore,
        connectTransportGrants: false,
        jellyfinApiProvider: () => perHostApi(down: down),
      );
      await model.initialize();
      await model.startDeviceLink();
      await pumpUntil(
        () => model.phase == SoupDeviceLinkPhase.ready,
        timeout: const Duration(seconds: 2),
      );
      expect(model.selectedServer?.id, 'home-jf');
      return model;
    }

    test('switches, persists the choice and stays ready', () async {
      final soupStore = MemorySoupSessionStore();
      final jellyfinStore = MemorySessionStore();
      final model = await readyModel(
        soupStore: soupStore,
        jellyfinStore: jellyfinStore,
      );
      addTearDown(model.dispose);
      final phases = <SoupDeviceLinkPhase>[];
      model.addListener(() => phases.add(model.phase));

      final error = await model.selectServer('test-jf');

      expect(error, isNull);
      expect(phases, everyElement(SoupDeviceLinkPhase.ready));
      expect(model.showsAuthShell, isFalse);
      expect(model.selectedServer?.id, 'test-jf');
      expect(model.switchingServerId, isNull);
      expect(model.jellyfinSession?.accessToken, 'token-test.tailnet.ts.net');
      expect(jellyfinStore.session?.accessToken, 'token-test.tailnet.ts.net');
      expect(model.session?.lastServerId, 'test-jf');
      expect(soupStore.session?.lastServerId, 'test-jf');
    });

    test('keeps the previous server when the exchange fails', () async {
      final soupStore = MemorySoupSessionStore();
      final jellyfinStore = MemorySessionStore();
      final model = await readyModel(
        soupStore: soupStore,
        jellyfinStore: jellyfinStore,
        down: {'test.tailnet.ts.net'},
      );
      addTearDown(model.dispose);

      final error = await model.selectServer('test-jf');

      expect(error, isNotNull);
      expect(model.phase, SoupDeviceLinkPhase.ready);
      expect(model.exchangeError, isNull);
      expect(model.selectedServer?.id, 'home-jf');
      expect(model.jellyfinSession?.accessToken, 'token-home.tailnet.ts.net');
      expect(jellyfinStore.session?.accessToken, 'token-home.tailnet.ts.net');
      expect(soupStore.session?.lastServerId, 'home-jf');
    });

    test('rejects a server that is not on the roster', () async {
      final model = await readyModel(
        soupStore: MemorySoupSessionStore(),
        jellyfinStore: MemorySessionStore(),
      );
      addTearDown(model.dispose);

      expect(await model.selectServer('gone'), isNotNull);
      expect(model.selectedServer?.id, 'home-jf');
    });
  });
}

/// Rejects the stored access token once, like a Soup session that expired
/// while the app was closed; everything else is the mock.
class ExpiredFirstClient implements SoupIdentityClient {
  ExpiredFirstClient(this.inner);

  final MockSoupIdentityClient inner;
  bool rejectedStaleToken = false;

  @override
  Future<ServerRoster> listServers(String accessToken) async {
    if (accessToken == 'stale-access') {
      rejectedStaleToken = true;
      throw const SoupIdentityException(
        'Soup Identity request failed',
        statusCode: 401,
      );
    }
    return inner.listServers(accessToken);
  }

  @override
  Future<DeviceLinkStart> startDeviceLink() => inner.startDeviceLink();

  @override
  Future<DeviceLinkPoll> pollDeviceLink(String deviceCode) =>
      inner.pollDeviceLink(deviceCode);

  @override
  Future<SoupSessionTokens> refreshSession(String refreshToken) =>
      inner.refreshSession(refreshToken);

  @override
  Future<void> revokeSession(String refreshToken) =>
      inner.revokeSession(refreshToken);

  @override
  Future<AssertionResponse> mintAssertion({
    required String accessToken,
    required String serverId,
  }) => inner.mintAssertion(accessToken: accessToken, serverId: serverId);

  @override
  void close() => inner.close();
}

class MemorySoupSessionStore implements SoupSessionStore {
  MemorySoupSessionStore([this.session]);

  SoupSession? session;

  @override
  Future<void> clear() async => session = null;

  @override
  Future<SoupSession?> read() async => session;

  @override
  Future<void> write(SoupSession value) async => session = value;
}

Future<void> pumpUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final end = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(end)) {
      fail('Condition not met before timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// Rotates refresh tokens strictly, like Soup Identity: each one works once.
class RotatingClient extends ExpiredFirstClient {
  RotatingClient(super.inner);

  String validRefresh = 'refresh-0';
  int refreshes = 0;
  bool failRoster = false;
  final rejectAccess = <String>{};
  final rosterTokens = <String>[];
  Completer<void>? _gate;

  Completer<void> holdRefresh() => _gate = Completer<void>();

  @override
  Future<SoupSessionTokens> refreshSession(String refreshToken) async {
    refreshes++;
    if (refreshToken != validRefresh) {
      throw const SoupIdentityException('Invalid refresh', statusCode: 401);
    }
    await _gate?.future;
    validRefresh = 'refresh-$refreshes';
    return SoupSessionTokens(
      accessToken: 'access-$refreshes',
      refreshToken: validRefresh,
      expiresIn: 900,
      tokenType: 'Bearer',
      email: 'dev@example.com',
    );
  }

  @override
  Future<ServerRoster> listServers(String accessToken) async {
    rosterTokens.add(accessToken);
    if (rejectAccess.contains(accessToken)) {
      throw const SoupIdentityException('Expired', statusCode: 401);
    }
    if (failRoster) {
      throw const SoupIdentityException('Unavailable', statusCode: 503);
    }
    return inner.listServers(accessToken);
  }
}

/// Hands out a grant's key on the first roster call only, like the server.
class OneShotGrantClient extends ExpiredFirstClient {
  OneShotGrantClient(super.inner);

  int rosterCalls = 0;

  @override
  Future<ServerRoster> listServers(String accessToken) async {
    final roster = await inner.listServers(accessToken);
    if (rosterCalls++ == 0) return roster;
    return ServerRoster(
      servers: [
        for (final s in roster.servers)
          RosterServer(
            id: s.id,
            name: s.name,
            audience: s.audience,
            magicDns: s.magicDns,
          ),
      ],
    );
  }
}

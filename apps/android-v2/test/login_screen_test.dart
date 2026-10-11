import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soup_core/soup_core.dart';
import 'package:soup_identity/soup_identity.dart';
import 'package:soup_tailscale/soup_tailscale.dart';
import 'package:soup_v2/src/features/auth/login_screen.dart';
import 'package:soup_v2/src/ui/theme/soup_theme.dart';

import 'support/connectivity_fakes.dart';

class _MemorySoupStore implements SoupSessionStore {
  SoupSession? session;
  @override
  Future<void> clear() async => session = null;
  @override
  Future<SoupSession?> read() async => session;
  @override
  Future<void> write(SoupSession value) async => session = value;
}

/// Emits whatever the test pushes; `complete` ends the search.
class _FakeDiscovery implements JellyfinDiscoveryService {
  final runs = <_FakeRun>[];
  @override
  JellyfinDiscoveryRun start(ConnectionMode mode, TailscaleProxy? proxy) {
    final run = _FakeRun();
    runs.add(run);
    return run;
  }
}

class _FakeRun implements JellyfinDiscoveryRun {
  final _controller = StreamController<JellyfinDiscoverySnapshot>.broadcast(
    sync: true,
  );
  @override
  Stream<JellyfinDiscoverySnapshot> get snapshots => _controller.stream;
  void push(List<DiscoveredJellyfinServer> servers, {bool done = true}) =>
      _controller.add(
        JellyfinDiscoverySnapshot(
          servers: servers,
          phase: done ? DiscoveryPhase.complete : DiscoveryPhase.searching,
        ),
      );
  @override
  void cancel() => unawaited(_controller.close());
}

DiscoveredJellyfinServer _server(DiscoverySource source) =>
    DiscoveredJellyfinServer(
      info: const JellyfinServerInfo(
        name: 'Living Room',
        version: '10.11.2',
        id: 'server-1',
      ),
      url: Uri.parse('http://192.168.1.20:8096'),
      sources: {source},
      rank: 0,
    );

/// The spinners never settle, so step the clock past focus and scale animations.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late SoupDeviceLinkViewModel soup;
  late ConnectivityViewModel connectivity;
  late FakeTailscaleClient tailscale;
  late _FakeDiscovery discovery;
  late int directSteps;

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 810);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(() {
      tester.view.reset();
      tester.platformDispatcher.clearAllTestValues();
    });
    tailscale = FakeTailscaleClient();
    discovery = _FakeDiscovery();
    connectivity = ConnectivityViewModel(
      tailscale,
      jellyfinClientFactory: FakeJellyfinClientFactory(),
      sessionStore: MemorySessionStore(),
      connectionStore: MemoryConnectionPreferencesStore(),
      discoveryService: discovery,
    );
    await connectivity.initialize();
    soup = SoupDeviceLinkViewModel(
      client: MockSoupIdentityClient(),
      sessionStore: _MemorySoupStore(),
      jellyfinSessionStore: MemorySessionStore(),
      jellyfinApiProvider: () async => throw UnimplementedError(),
      connectTransportGrants: false,
    );
    await soup.initialize();
    await soup.startDeviceLink();
    directSteps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: SoupTheme.dark,
        home: LoginScreen(
          viewModel: soup,
          connectivity: connectivity,
          onDirectStep: () async => directSteps++,
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> tearDownScreen(WidgetTester tester) async {
    // Stop the device-link poll timer before the framework checks for leaks.
    await tester.pumpWidget(const SizedBox());
    soup.dispose();
    connectivity.dispose();
    tailscale.dispose();
  }

  testWidgets('shows the QR, discovery and Tailscale on one card', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(soup.phase, SoupDeviceLinkPhase.waiting);
    // A fresh setup moves to the server step so discovery can run.
    expect(connectivity.phase, SetupPhase.server);
    expect(discovery.runs, hasLength(1));
    expect(find.text('Scan with your phone'), findsOneWidget);
    expect(find.text('Looking for servers…'), findsOneWidget);
    expect(find.text('Enter address'), findsOneWidget);
    expect(find.bySemanticsLabel('Use Tailscale'), findsOneWidget);
    expect(find.text('Use Tailscale'), findsNothing);
    // The card and its hint fit the 1440×810 design canvas without scrolling.
    final hint = tester.getRect(
      find.text('Pick a server, or scan the code with your phone'),
    );
    expect(hint.bottom, lessThan(810));

    discovery.runs.single.push([]);
    await tester.pump();
    expect(find.text('No servers found yet'), findsOneWidget);

    await tearDownScreen(tester);
  });

  testWidgets('picking a discovered server opens the Jellyfin form', (
    tester,
  ) async {
    await pumpScreen(tester);

    discovery.runs.single.push([_server(DiscoverySource.local)]);
    await tester.pump();
    expect(find.text('Living Room'), findsOneWidget);
    expect(find.text('LOCAL'), findsOneWidget);

    await tester.tap(find.text('Living Room'));
    await settle(tester);
    expect(directSteps, 1);
    expect(connectivity.phase, SetupPhase.credentials);

    await tearDownScreen(tester);
  });

  testWidgets('Enter address hands off to the manual server form', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Enter address'));
    await settle(tester);
    expect(directSteps, 1);
    expect(connectivity.showingServerDiscovery, isFalse);

    await tearDownScreen(tester);
  });

  testWidgets('the Tailscale button runs Tailscale sign-in in the card', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.tap(find.bySemanticsLabel('Use Tailscale'));
    await settle(tester);
    expect(connectivity.tailscaleEnabled, isTrue);
    expect(find.text('Connect with Tailscale'), findsOneWidget);
    expect(find.text('Waiting for sign-in'), findsOneWidget);

    // Signing in returns to the card, where the tailnet is searched too.
    tailscale.complete();
    await settle(tester);
    expect(find.text('Connect with Tailscale'), findsNothing);
    expect(connectivity.phase, SetupPhase.server);
    discovery.runs.last.push([_server(DiscoverySource.tailscale)]);
    await tester.pump();
    expect(find.text('TAILSCALE'), findsOneWidget);
    expect(find.bySemanticsLabel('Tailscale, connected'), findsOneWidget);

    await tearDownScreen(tester);
  });

  testWidgets('Back from an unfinished Tailscale sign-in turns it off', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.tap(find.bySemanticsLabel('Use Tailscale'));
    await settle(tester);
    await tester.tap(find.text('Back'));
    await settle(tester);
    expect(find.text('Connect with Tailscale'), findsNothing);
    expect(connectivity.tailscaleEnabled, isFalse);
    expect(connectivity.phase, SetupPhase.server);

    await tearDownScreen(tester);
  });
}

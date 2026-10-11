import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soup_core/soup_core.dart';
import 'package:soup_v2/src/features/auth/direct_login_screen.dart';
import 'package:soup_v2/src/ui/theme/soup_theme.dart';
import 'package:soup_v2/src/ui/widgets/soup_text_field.dart';

import 'support/connectivity_fakes.dart';

Finder _field(String key) => find.descendant(
  of: find.byKey(ValueKey(key)),
  matching: find.byType(TextField),
);

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  late FakeTailscaleClient tailscale;
  late MemoryConnectionPreferencesStore preferences;
  late ConnectivityViewModel model;

  // Built inside the test body: view-model futures must run in the test's
  // fake-async zone, which setUp callbacks are not part of.
  void makeModel() {
    TvTextInput.resetForTesting();
    tailscale = FakeTailscaleClient();
    preferences = MemoryConnectionPreferencesStore();
    model = ConnectivityViewModel(
      tailscale,
      jellyfinClientFactory: FakeJellyfinClientFactory(),
      sessionStore: MemorySessionStore(),
      connectionStore: preferences,
    );
    addTearDown(() {
      model.dispose();
      tailscale.dispose();
    });
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    VoidCallback? onUseSoupInvite,
  }) async {
    makeModel();
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    // Stops the poster wall's endless marquee so pumpAndSettle can finish.
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(() {
      tester.view.reset();
      tester.platformDispatcher.clearAllTestValues();
    });
    await model.initialize();
    await tester.pumpWidget(
      MaterialApp(
        theme: SoupTheme.dark,
        home: DirectLoginScreen(
          viewModel: model,
          onUseSoupInvite: onUseSoupInvite,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('walks connection → server → credentials → signed in', (
    tester,
  ) async {
    await pumpScreen(tester);

    // Step 1: direct connection is allowed without Tailscale.
    expect(find.text('Connect to Jellyfin'), findsOneWidget);
    expect(find.text('Use Tailscale'), findsOneWidget);
    expect(
      find.text('Select Next to connect directly to Jellyfin.'),
      findsOneWidget,
    );
    await _tap(tester, 'connection-next-button');
    expect(model.phase, SetupPhase.server);
    expect(preferences.mode, ConnectionMode.direct);

    // Step 2: no discovery service, so the manual address field is shown.
    expect(find.text('Find your server'), findsOneWidget);
    await tester.enterText(_field('server-url-field'), 'jellyfin:8096');
    await _tap(tester, 'check-server-button');
    expect(model.phase, SetupPhase.credentials);

    // Step 3: credentials alongside Quick Connect.
    expect(find.text('Sign in to Living Room'), findsOneWidget);
    expect(find.byKey(const ValueKey('quick-connect-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('password-panel')), findsOneWidget);
    await tester.enterText(_field('username-field'), 'Michael');
    await tester.enterText(_field('password-field'), 'secret');
    await _tap(tester, 'sign-in-button');
    expect(model.phase, SetupPhase.ready);
    expect(model.session?.userName, 'Michael');
  });

  testWidgets('typing a scheme moves it onto the protocol chip', (
    tester,
  ) async {
    await pumpScreen(tester);
    await _tap(tester, 'connection-next-button');
    expect(find.text('https://'), findsOneWidget);
    await tester.enterText(_field('server-url-field'), 'http://jellyfin:8096');
    await tester.pump();
    expect(find.text('http://'), findsOneWidget);
    expect(
      tester.widget<TextField>(_field('server-url-field')).controller!.text,
      'jellyfin:8096',
    );
  });

  testWidgets('Back returns from credentials to the server step', (
    tester,
  ) async {
    await pumpScreen(tester);
    await model.continueConnection();
    await model.checkServer('http://jellyfin:8096');
    await tester.pumpAndSettle();
    expect(model.phase, SetupPhase.credentials);
    await _tap(tester, 'onboarding-back-button');
    expect(model.phase, SetupPhase.server);
  });

  testWidgets('offers "Use Soup invite instead" on the first step', (
    tester,
  ) async {
    var used = 0;
    await pumpScreen(tester, onUseSoupInvite: () => used++);
    await tester.tap(
      find.byKey(const ValueKey('connectivity-use-soup-invite')),
    );
    expect(used, 1);
  });

  testWidgets(
    'Tailscale toggle shows the interactive login QR and gates Next',
    (tester) async {
      await pumpScreen(tester);
      await _tap(tester, 'tailscale-toggle');
      expect(model.tailscaleEnabled, isTrue);
      expect(
        find.byKey(const ValueKey('tailscale-authorization')),
        findsOneWidget,
      );
      expect(find.text('Scan to sign in'), findsOneWidget);
      // Next is dimmed until Tailscale is connected.
      expect(
        tester
            .widget<Opacity>(
              find.descendant(
                of: find.byKey(const ValueKey('connection-next-button')),
                matching: find.byType(Opacity),
              ),
            )
            .opacity,
        lessThan(1),
      );
      tailscale.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tailscale-connected')), findsOneWidget);
    },
  );
}

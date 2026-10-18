import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:soup_core/soup_core.dart';
import 'package:soup_v2/src/app_scope.dart';
import 'package:soup_v2/src/data/mock_catalog.dart';
import 'package:soup_v2/src/data/models.dart';
import 'package:soup_v2/src/data/playback_prefs.dart';
import 'package:soup_v2/src/form_factor.dart';
import 'package:soup_v2/src/features/playback/playback_screen.dart';
import 'package:soup_v2/src/features/playback/speed_controller.dart';
import 'package:soup_v2/src/ui/soup_focus_policy.dart';
import 'package:soup_v2/src/ui/theme/soup_theme.dart';
import 'package:soup_v2/src/ui/widgets/soup_button.dart';

final _session = JellyfinSession(
  serverUrl: Uri.parse('http://jellyfin/'),
  serverId: 'server',
  userId: 'user',
  userName: 'Alex',
  accessToken: 'token',
);

MockClient _client({List<http.Request>? log}) => MockClient((request) async {
  log?.add(request);
  if (request.url.path.endsWith('/PlaybackInfo')) {
    return http.Response(
      '{"PlaySessionId":"play","MediaSources":[{"Id":"source","Container":"mp4",'
      '"SupportsDirectPlay":true,"TranscodingUrl":"/Videos/x/master.m3u8?MediaSourceId=source",'
      '"MediaStreams":[{"Type":"Subtitle","Index":3,"Codec":"srt","Language":"eng","DisplayTitle":"English"}]}]}',
      200,
    );
  }
  if (request.url.path.contains('/Subtitles/')) {
    return http.Response('WEBVTT\n\n00:00.000 --> 00:02.000\nHi\n', 200);
  }
  return http.Response('', 204);
});

/// The Direct/Transcode pill lives in the settings panel.
Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('settings-button')));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _pumpPlayer(
  WidgetTester tester, {
  required FakeFactory factory,
  required CatalogItem item,
  bool live = true,
  PlaybackPrefs? prefs,
  int startTicks = 0,
  int? audioIndex,
  List<http.Request>? log,
  bool touch = false,
}) async {
  // Touch: a landscape phone (844×390 logical).
  tester.view.physicalSize = touch
      ? const Size(844, 390)
      : const Size(960, 540);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final client = _client(log: log);
  addTearDown(client.close);
  final catalog = MockCatalog();
  addTearDown(catalog.dispose);
  final p = prefs ?? PlaybackPrefs();
  await tester.pumpWidget(
    SoupScope(
      catalog: catalog,
      prefs: p,
      api: live ? JellyfinApi(client, deviceId: 'device') : null,
      session: live ? _session : null,
      onSignOut: () async {},
      child: MaterialApp(
        theme: SoupTheme.dark,
        // Same D-pad traversal as the app (DesignScale installs it there).
        builder: (context, child) => FormFactorScope(
          value: touch ? FormFactor.touch : FormFactor.tv,
          child: FocusTraversalGroup(policy: SoupFocusPolicy(), child: child!),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PlaybackScreen(
                    item: item,
                    startTicks: startTicks,
                    audioIndex: audioIndex,
                    controllerFactory: factory,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _back(WidgetTester tester) async {
  final dynamic app = tester.state(find.byType(WidgetsApp));
  await app.didPopRoute();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

double _chromeOpacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(find.byKey(const ValueKey('playback-chrome')))
    .opacity;

const _movie = CatalogItem(
  id: 'm1',
  name: 'Northlight',
  type: 'Movie',
  productionYear: 2023,
  mediaStreams: [
    MediaStreamInfo(
      index: 1,
      kind: StreamKind.audio,
      language: 'eng',
      displayTitle: 'English',
      isDefault: true,
    ),
    MediaStreamInfo(
      index: 2,
      kind: StreamKind.audio,
      language: 'jpn',
      displayTitle: 'Japanese',
    ),
    MediaStreamInfo(
      index: 3,
      kind: StreamKind.subtitle,
      language: 'eng',
      isTextSubtitle: true,
    ),
  ],
  chapters: [
    Chapter(name: 'Chapter 1', startTicks: 0),
    Chapter(name: 'Chapter 2', startTicks: 600 * 10000000),
  ],
);

void main() {
  _touchTests();
  _trickplayTests();

  testWidgets('direct play shows the Direct pill and starts playing', (
    tester,
  ) async {
    final factory = FakeFactory();
    await _pumpPlayer(tester, factory: factory, item: _movie);
    expect(factory.controllers, hasLength(1));
    expect(
      factory.controllers.single.uri.path,
      endsWith('/Videos/m1/stream.mp4'),
    );
    await _openSettings(tester);
    expect(find.text('Direct'), findsOneWidget);
    expect(find.byKey(const ValueKey('playback-title')), findsOneWidget);
    expect(factory.controllers.single.value.playing, isTrue);
  });

  testWidgets('leaving while the player loads never starts playback', (
    tester,
  ) async {
    final gate = Completer<void>();
    final factory = FakeFactory(initializeGate: gate);
    await _pumpPlayer(tester, factory: factory, item: _movie);
    expect(factory.controllers, hasLength(1));
    await _back(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(PlaybackScreen), findsNothing);
    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final controller = factory.controllers.single;
    expect(controller.value.playing, isFalse);
    expect(controller.closes, greaterThan(0));
    expect(factory.controllers, hasLength(1));
  });

  Map<String, Object?> lastReport(List<http.Request> log, String kind) =>
      jsonDecode(
            log.lastWhere((r) => r.url.path == '/Sessions/Playing/$kind').body,
          )
          as Map<String, Object?>;

  testWidgets('Try again resumes where playback failed, as a new session', (
    tester,
  ) async {
    final log = <http.Request>[];
    final factory = FakeFactory();
    await _pumpPlayer(tester, factory: factory, item: _movie, log: log);
    await factory.controllers.last.seekTo(const Duration(minutes: 40));
    // Direct play fails, then its transcode fallback fails too.
    factory.controllers.last.failNow();
    await tester.pump(const Duration(milliseconds: 100));
    factory.controllers.last.failNow();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('playback-error')), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const ValueKey('playback-error')), findsNothing);
    expect(
      factory.controllers.last.value.position,
      const Duration(minutes: 40),
    );
    expect(factory.controllers.last.value.playing, isTrue);
    expect(lastReport(log, 'Stopped')['PositionTicks'], 40 * 60 * 10000000);
  });

  testWidgets('a pause from outside the controls is reported', (tester) async {
    final log = <http.Request>[];
    final factory = FakeFactory();
    await _pumpPlayer(tester, factory: factory, item: _movie, log: log);
    expect(lastReport(log, 'Progress')['IsPaused'], isFalse);

    // e.g. the OS pausing the player when the app goes to the background.
    await factory.controllers.single.pause();
    await tester.pump();

    expect(lastReport(log, 'Progress')['IsPaused'], isTrue);
    // Paused sessions keep pinging so Jellyfin doesn't drop them.
    final before = log.length;
    await tester.pump(const Duration(seconds: 31));
    expect(log.length, greaterThan(before));
    expect(lastReport(log, 'Progress')['IsPaused'], isTrue);
  });

  testWidgets('leaving straight after a seek saves the seek target', (
    tester,
  ) async {
    final log = <http.Request>[];
    final factory = FakeFactory();
    await _pumpPlayer(tester, factory: factory, item: _movie, log: log);
    await tester.pump(const Duration(seconds: 5)); // chrome hides
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    Navigator.of(tester.element(find.byType(PlaybackScreen))).pop();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(lastReport(log, 'Stopped')['PositionTicks'], 10 * 10000000);
  });

  testWidgets('falls back from failed direct play to transcode', (
    tester,
  ) async {
    final factory = FakeFactory(failures: 1);
    await _pumpPlayer(
      tester,
      factory: factory,
      item: _movie,
      startTicks: 150000000,
    );
    expect(factory.controllers, hasLength(2));
    expect(
      factory.controllers.last.uri.path,
      endsWith('/Videos/x/master.m3u8'),
    );
    await _openSettings(tester);
    expect(find.text('Transcode'), findsOneWidget);
    expect(
      factory.controllers.last.value.position,
      const Duration(seconds: 15),
    );
  });

  testWidgets('the error overlay takes the D-pad from the player', (
    tester,
  ) async {
    final factory = FakeFactory(failures: 2);
    await _pumpPlayer(tester, factory: factory, item: _movie);
    expect(find.byKey(const ValueKey('playback-error')), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Try again');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, isNot('Try again'));
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<SoupButton>()
          ?.label,
      'Back',
    );
  });

  testWidgets('explicit audio track forces a transcode with that stream', (
    tester,
  ) async {
    final factory = FakeFactory();
    await _pumpPlayer(tester, factory: factory, item: _movie, audioIndex: 2);
    expect(
      factory.controllers.single.uri.queryParameters['AudioStreamIndex'],
      '2',
    );
    await _openSettings(tester);
    expect(find.text('Transcode'), findsOneWidget);
  });

  testWidgets('chrome auto-hides, any D-pad key reveals it, Left/Right seek', (
    tester,
  ) async {
    final factory = FakeFactory();
    await _pumpPlayer(tester, factory: factory, item: _movie);
    expect(_chromeOpacity(tester), 1);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_chromeOpacity(tester), 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 300));
    expect(_chromeOpacity(tester), 1);
    expect(
      factory.controllers.single.value.position,
      const Duration(seconds: 10),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(factory.controllers.single.value.position, Duration.zero);
  });

  testWidgets('Select toggles play/pause while the chrome is hidden', (
    tester,
  ) async {
    final factory = FakeFactory();
    await _pumpPlayer(tester, factory: factory, item: _movie);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_chromeOpacity(tester), 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 300));
    expect(factory.controllers.single.value.playing, isFalse);
    expect(_chromeOpacity(tester), 1);
    // Paused: the chrome stays up.
    await tester.pump(const Duration(seconds: 6));
    expect(_chromeOpacity(tester), 1);
  });

  testWidgets('skip intro appears inside the segment and seeks to its end', (
    tester,
  ) async {
    final factory = FakeFactory();
    await _pumpPlayer(tester, factory: factory, item: _movie);
    expect(find.byKey(const ValueKey('skip-button')), findsNothing);
    await factory.controllers.single.seekTo(const Duration(seconds: 40));
    await tester.pump();
    expect(find.text('Skip intro'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('skip-button')));
    await tester.pump();
    expect(
      factory.controllers.single.value.position,
      const Duration(seconds: 75),
    );
    await tester.pump();
    expect(find.text('Skip intro'), findsNothing);
  });

  testWidgets('autoSkipIntros jumps past the intro without a click', (
    tester,
  ) async {
    final factory = FakeFactory();
    final prefs = PlaybackPrefs()..autoSkipIntros = true;
    await _pumpPlayer(tester, factory: factory, item: _movie, prefs: prefs);
    await factory.controllers.single.seekTo(const Duration(seconds: 40));
    await tester.pump();
    await tester.pump();
    expect(
      factory.controllers.single.value.position,
      const Duration(seconds: 75),
    );
  });

  testWidgets(
    'settings panel: speed, subtitle switch reloads with VTT; Back closes then exits',
    (tester) async {
      final factory = FakeFactory();
      final log = <http.Request>[];
      await _pumpPlayer(tester, factory: factory, item: _movie, log: log);
      await tester.tap(find.byKey(const ValueKey('settings-button')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('panel-Settings')), findsOneWidget);
      expect(find.text('SPEED'), findsOneWidget);
      expect(find.text('English'), findsWidgets);

      await tester.tap(find.text('1.5×'));
      await tester.pump();
      expect(factory.controllers.single.speed, 1.5);

      // Subtitles list before Audio, so the first "English" is the subtitle
      // track; scroll it into view below the method pill first.
      await tester.ensureVisible(find.text('English').first);
      await tester.pump();
      await tester.tap(find.text('English').first);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('panel-Settings')), findsNothing);
      expect(factory.controllers, hasLength(2));
      expect(factory.controllers.last.hadSubtitles, isTrue);
      expect(factory.controllers.last.speed, 1.5);
      expect(log.any((r) => r.url.path.contains('/Subtitles/3/')), isTrue);

      // Back closes an open panel first, then leaves the player.
      await tester.tap(find.byKey(const ValueKey('chapters-button')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('panel-Chapters')), findsOneWidget);
      await _back(tester);
      expect(find.byKey(const ValueKey('panel-Chapters')), findsNothing);
      expect(find.byType(PlaybackScreen), findsOneWidget);
      await _back(tester);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(PlaybackScreen), findsNothing);
      expect(log.any((r) => r.url.path == '/Sessions/Playing/Stopped'), isTrue);
    },
  );

  testWidgets('D-pad reaches the settings panel and Left closes it', (
    tester,
  ) async {
    final factory = FakeFactory();
    await _pumpPlayer(tester, factory: factory, item: _movie);
    // play button is focused; walk down to the bottom bar and across to Settings.
    String where() =>
        FocusManager.instance.primaryFocus?.debugLabel ??
        '${FocusManager.instance.primaryFocus?.context?.widget.runtimeType}';
    expect(where(), 'playback play');
    for (var i = 0; i < 2; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
    }
    expect(where(), isNot('playback seek')); // now on the button row
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('panel-Settings')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('panel-Settings')), findsNothing);
  });

  testWidgets('chapters panel seeks to the chosen chapter', (tester) async {
    final factory = FakeFactory();
    await _pumpPlayer(tester, factory: factory, item: _movie);
    await tester.tap(find.byKey(const ValueKey('chapters-button')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Chapter 2'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      factory.controllers.single.value.position,
      const Duration(minutes: 10),
    );
    expect(find.byKey(const ValueKey('panel-Chapters')), findsNothing);
  });

  testWidgets(
    'Select on the Chapters button opens the panel and leaves it open',
    (tester) async {
      final factory = FakeFactory();
      await _pumpPlayer(tester, factory: factory, item: _movie);
      await factory.controllers.single.seekTo(const Duration(minutes: 12));
      await tester.pump();
      final chapters = find.byKey(const ValueKey('chapters-button'));
      Focus.of(
        tester.element(
          find.descendant(of: chapters, matching: find.byType(Container)).first,
        ),
      ).requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.pump();
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('panel-Chapters')), findsOneWidget);
      expect(
        factory.controllers.single.value.position,
        const Duration(minutes: 12),
      );
    },
  );

  testWidgets('next-episode card counts down and replaces the route', (
    tester,
  ) async {
    final factory = FakeFactory();
    final catalog = MockCatalog();
    final episode = await catalog.item('s1-s1e1');
    catalog.dispose();
    await _pumpPlayer(tester, factory: factory, item: episode);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('next-episode-countdown')), findsNothing);
    final c = factory.controllers.single;
    await c.seekTo(c.value.duration - const Duration(seconds: 20));
    await tester.pump();
    expect(find.text('Next episode in 10'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Next episode in 7'), findsOneWidget);

    // Back dismisses the card without leaving.
    await _back(tester);
    expect(find.byKey(const ValueKey('next-episode-countdown')), findsNothing);
    expect(find.byType(PlaybackScreen), findsOneWidget);
  });

  testWidgets('autoplay next: counting down to zero starts the next episode', (
    tester,
  ) async {
    final factory = FakeFactory();
    final catalog = MockCatalog();
    final episode = await catalog.item('s1-s1e1');
    catalog.dispose();
    await _pumpPlayer(tester, factory: factory, item: episode);
    await tester.pump(const Duration(milliseconds: 200));
    final c = factory.controllers.single;
    await c.seekTo(c.value.duration - const Duration(seconds: 20));
    await tester.pump();
    await tester.pump(const Duration(seconds: 11));
    // The next player binds a real loopback socket; give the event loop time.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(factory.controllers, hasLength(2));
    expect(find.byType(PlaybackScreen), findsOneWidget);
  });

  testWidgets('mock mode plays the public sample directly', (tester) async {
    final factory = FakeFactory();
    await _pumpPlayer(tester, factory: factory, item: _movie, live: false);
    expect(factory.controllers.single.uri.toString(), mockSampleUrl);
    await _openSettings(tester);
    expect(find.text('Direct'), findsOneWidget);
  });
}

void _touchTests() {
  testWidgets('touch: settings opens one sheet with Audio, Speed, Quality', (
    tester,
  ) async {
    final factory = FakeFactory();
    await _pumpPlayer(tester, factory: factory, item: _movie, touch: true);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('fill-button')), findsOneWidget);
    expect(find.text('1×'), findsNothing); // no speed in the chrome

    await tester.tap(find.byKey(const ValueKey('settings-button')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('panel-Settings')), findsOneWidget);
    expect(find.text('AUDIO'), findsOneWidget);
    expect(find.text('SUBTITLES'), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-tab-Quality')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('settings-tab-Speed')));
    await tester.pump();
    await tester.tap(find.text('1.5×'));
    await tester.pump();
    expect(factory.controllers.single.speed, 1.5);

    await tester.tap(find.byKey(const ValueKey('settings-tab-Quality')));
    await tester.pump();
    expect(find.text('Auto'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _back(tester);
    expect(find.byKey(const ValueKey('panel-Settings')), findsNothing);
    expect(find.byType(PlaybackScreen), findsOneWidget);
  });

  testWidgets('touch: lock hides the controls until unlocked', (tester) async {
    final factory = FakeFactory();
    await _pumpPlayer(tester, factory: factory, item: _movie, touch: true);
    await tester.tap(find.byKey(const ValueKey('lock-button')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_chromeOpacity(tester), 0);
    expect(find.byKey(const ValueKey('unlock-button')), findsOneWidget);

    // Back is swallowed while locked.
    await _back(tester);
    expect(find.byType(PlaybackScreen), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('unlock-button')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_chromeOpacity(tester), 1);
    expect(find.byKey(const ValueKey('unlock-button')), findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('touch: taps after a double-tap keep stacking the seek', (
    tester,
  ) async {
    final factory = FakeFactory();
    await _pumpPlayer(tester, factory: factory, item: _movie, touch: true);
    final start = factory.controllers.single.value.position;
    const at = Offset(760, 200); // right half, clear of the chrome
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('+10 s'), findsOneWidget);
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('+20 s'), findsOneWidget);
    expect(
      factory.controllers.single.value.position,
      start + const Duration(seconds: 20),
    );
    await tester.pump(const Duration(seconds: 5));
  });
}

/// [_movie] with seek thumbnails for the source PlaybackInfo picks.
final _withTrickplay = CatalogItem(
  id: _movie.id,
  name: _movie.name,
  type: _movie.type,
  chapters: _movie.chapters,
  trickplay: const {
    'source': Trickplay(
      width: 320,
      height: 180,
      tileWidth: 10,
      tileHeight: 10,
      thumbnailCount: 540,
      interval: Duration(seconds: 10),
    ),
  },
);

void _trickplayTests() {
  testWidgets('TV: seeking shows the trickplay thumbnail, then hides it', (
    tester,
  ) async {
    final factory = FakeFactory();
    await _pumpPlayer(tester, factory: factory, item: _withTrickplay);
    final preview = find.byKey(const ValueKey('trickplay-preview'));
    expect(preview, findsNothing);
    // Once the chrome hides, Right seeks (and focuses the seek bar).
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(preview, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1600));
    expect(preview, findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('TV: no thumbnail when the server made none', (tester) async {
    final factory = FakeFactory();
    await _pumpPlayer(tester, factory: factory, item: _movie);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.byKey(const ValueKey('trickplay-preview')), findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('touch: scrubbing shows the thumbnail in the bubble', (
    tester,
  ) async {
    final factory = FakeFactory();
    await _pumpPlayer(
      tester,
      factory: factory,
      item: _withTrickplay,
      touch: true,
    );
    final bar = find.byKey(const ValueKey('playback-seekbar'));
    final gesture = await tester.startGesture(tester.getCenter(bar));
    await tester.pump();
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump();
    expect(find.byKey(const ValueKey('trickplay-preview')), findsOneWidget);
    await gesture.up();
    await tester.pump();
    expect(find.byKey(const ValueKey('trickplay-preview')), findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });
}

class FakeFactory implements SoupVideoControllerFactory {
  FakeFactory({this.failures = 0, this.initializeGate});
  int failures;

  /// When set, every controller's initialize waits on it.
  final Completer<void>? initializeGate;
  final controllers = <FakeController>[];

  @override
  SoupVideoController create(Uri uri, {Future<String>? subtitleVtt}) {
    final c = FakeController(
      uri,
      hadSubtitles: subtitleVtt != null,
      fail: failures-- > 0,
      gate: initializeGate,
    );
    controllers.add(c);
    return c;
  }
}

class FakeController extends ChangeNotifier
    implements SoupVideoController, SpeedControllable {
  FakeController(
    this.uri, {
    required this.hadSubtitles,
    required this.fail,
    this.gate,
  });
  final Uri uri;
  final bool hadSubtitles;
  final bool fail;
  final Completer<void>? gate;
  int closes = 0;
  double speed = 1;
  SoupVideoValue _value = const SoupVideoValue();

  @override
  SoupVideoValue get value => _value;

  void _set({bool? playing, Duration? position}) {
    _value = SoupVideoValue(
      initialized: _value.initialized,
      playing: playing ?? _value.playing,
      position: position ?? _value.position,
      duration: _value.duration,
    );
    notifyListeners();
  }

  @override
  Future<void> initialize() async {
    await gate?.future;
    if (fail) throw StateError('direct playback failed');
    _value = const SoupVideoValue(
      initialized: true,
      duration: Duration(minutes: 90),
    );
    notifyListeners();
  }

  @override
  Future<void> play() async => _set(playing: true);

  @override
  Future<void> pause() async => _set(playing: false);

  @override
  Future<void> seekTo(Duration position) async => _set(position: position);

  @override
  Future<void> setSpeed(double value) async => speed = value;

  @override
  Widget buildView() => const SizedBox.expand();

  @override
  Future<void> close() async => closes++;

  /// A media error mid-stream, as the platform player reports one.
  void failNow() {
    _value = SoupVideoValue(
      initialized: _value.initialized,
      position: _value.position,
      duration: _value.duration,
      error: 'decoder failed',
    );
    notifyListeners();
  }
}

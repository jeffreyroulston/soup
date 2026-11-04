import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soup_v2/src/app_scope.dart';
import 'package:soup_v2/src/data/mock_catalog.dart';
import 'package:soup_v2/src/data/mock_seerr.dart';
import 'package:soup_v2/src/data/playback_prefs.dart';
import 'package:soup_v2/src/data/seerr.dart';
import 'package:soup_v2/src/data/seerr_models.dart';
import 'package:soup_v2/src/features/explore/explore_requests_screen.dart';
import 'package:soup_v2/src/features/explore/explore_screen.dart';
import 'package:soup_v2/src/features/explore/explore_title_screen.dart';
import 'package:soup_v2/src/features/explore/request_flow.dart';
import 'package:soup_v2/src/features/explore/seerr_card.dart';
import 'package:soup_v2/src/features/explore/seerr_request_card.dart';
import 'package:soup_v2/src/features/explore/seerr_unavailable.dart';
import 'package:soup_v2/src/features/home/home_screen.dart';
import 'package:soup_v2/src/form_factor.dart';
import 'package:soup_v2/src/ui/theme/soup_theme.dart';
import 'package:soup_v2/src/ui/touch/touch_frame.dart';
import 'package:soup_v2/src/ui/touch/touch_scaffold.dart';
import 'package:soup_v2/src/ui/widgets/glass_nav.dart';
import 'package:soup_v2/src/ui/widgets/page_scaffold.dart';
import 'package:soup_v2/src/ui/widgets/soup_button.dart';

/// Explore on the mock catalogue, TV (1440×810) or a phone (412×915 @2.625).
Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  bool touch = false,
  Seerr? seerr,
}) async {
  if (touch) {
    tester.view.physicalSize = const Size(412, 915) * 2.625;
    tester.view.devicePixelRatio = 2.625;
  } else {
    tester.view.physicalSize = const Size(1440, 810);
    tester.view.devicePixelRatio = 1;
  }
  addTearDown(tester.view.reset);
  final catalog = MockCatalog();
  if (seerr != null) Seerr.install(catalog, seerr);
  final prefs = PlaybackPrefs();
  await tester.pumpWidget(
    MaterialApp(
      theme: SoupTheme.dark,
      builder: (context, child) => touch
          ? FormFactorScope(
              value: FormFactor.touch,
              child: TouchFrame(child: child!),
            )
          : child!,
      home: SoupScope(
        catalog: catalog,
        prefs: prefs,
        userLabel: 'mock@soup.dev',
        onSignOut: () async {},
        child: home,
      ),
    ),
  );
  await _settle(tester);
}

/// Mock artwork renders through dart:ui and the mock Seerr answers after a
/// delay, both of which need real async.
Future<void> _settle(WidgetTester tester) async {
  // Each round lets one layer of mock delays fire (status → rows → tiles),
  // with real time in between for the artwork.
  for (var round = 0; round < 3; round++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
}

Future<void> _tapButton(WidgetTester tester, String label) async {
  final button = find.ancestor(
    of: find.text(label),
    matching: find.byType(SoupButton),
  );
  expect(button, findsOneWidget);
  await tester.tap(button);
  await _settle(tester);
}

void main() {
  group('models', () {
    test('results map titles and people, flagging what the library has', () {
      final results = mapSeerrResults({
        'page': 1,
        'totalPages': 1,
        'totalResults': 3,
        'results': [
          {
            'id': 1,
            'mediaType': 'movie',
            'title': 'A Film',
            'releaseDate': '2001-04-05',
            'posterPath': '/a.jpg',
            'mediaInfo': {
              'id': 9,
              'tmdbId': 1,
              'status': 5,
              'jellyfinMediaId': 'jf1',
            },
          },
          {
            'id': 2,
            'mediaType': 'tv',
            'name': 'A Show',
            'firstAirDate': '1999-01-01',
            'mediaInfo': {'id': 10, 'tmdbId': 2, 'status': 3},
          },
          {'id': 3, 'mediaType': 'person', 'name': 'Someone'},
          {'id': 4, 'mediaType': 'collection', 'name': 'skipped'},
        ],
      });
      expect(results.titles.map((t) => t.title), ['A Film', 'A Show']);
      expect(results.titles.first.year, 2001);
      expect(results.titles.first.mediaInfo?.jellyfinMediaId, 'jf1');
      expect(
        availabilityLabel(results.titles.first.mediaInfo),
        'In your library',
      );
      expect(availabilityLabel(results.titles.last.mediaInfo), 'On its way');
      expect(results.people.single.name, 'Someone');
    });

    test('nothing to request once every season is covered', () {
      final info = mapSeerrMediaInfo({
        'id': 1,
        'tmdbId': 1,
        'status': 4,
        'seasons': [
          {'seasonNumber': 1, 'status': 5},
          {'seasonNumber': 2, 'status': 3},
        ],
      }, SeerrMediaType.tv);
      final seasons = [
        for (var n = 1; n <= 3; n++)
          SeerrSeason(seasonNumber: n, name: 'Season $n', episodeCount: 6),
      ];
      expect(nothingToRequest(info, seasons), isFalse);
      expect(nothingToRequest(info, seasons.take(2).toList()), isTrue);
      expect(seasonStatusLabel(seasonStatus(info, 2)), 'On its way');
      expect(seasonStatus(info, 3), isNull);
    });

    test('a tv payload asks for all seasons or a list', () {
      const all = SeerrRequestPayload(
        mediaType: SeerrMediaType.tv,
        mediaId: 7,
        allSeasons: true,
      );
      const some = SeerrRequestPayload(
        mediaType: SeerrMediaType.tv,
        mediaId: 7,
        seasons: [1, 3],
      );
      expect(all.toJson()['seasons'], 'all');
      expect(some.toJson()['seasons'], [1, 3]);
      expect(
        const SeerrRequestPayload(
          mediaType: SeerrMediaType.movie,
          mediaId: 7,
        ).toJson().containsKey('seasons'),
        isFalse,
      );
    });

    test('permissions gate requests by kind', () {
      const viewer = SeerrUser(id: 1, displayName: 'v');
      const movies = SeerrUser(
        id: 2,
        displayName: 'm',
        permissions: SeerrPermission.requestMovie,
      );
      const admin = SeerrUser(
        id: 3,
        displayName: 'a',
        permissions: SeerrPermission.admin,
      );
      expect(viewer.canRequest(SeerrMediaType.movie), isFalse);
      expect(movies.canRequest(SeerrMediaType.movie), isTrue);
      expect(movies.canRequest(SeerrMediaType.tv), isFalse);
      expect(admin.canRequest(SeerrMediaType.tv), isTrue);
    });
  });

  testWidgets('TV nav grows an Explore tab once Seerr answers', (tester) async {
    await _pump(tester, const HomeScreen());
    expect(find.byType(GlassNav), findsOneWidget);
    expect(find.text('Explore'), findsOneWidget);
    expect(find.text('My Stuff'), findsOneWidget);
  });

  testWidgets('TV nav hides Explore when Seerr is not set up', (tester) async {
    await _pump(tester, const HomeScreen(), seerr: _UnconfiguredSeerr());
    expect(find.text('Explore'), findsNothing);
  });

  testWidgets('Down from the nav lands on the section tab, not the field', (
    tester,
  ) async {
    await _pump(tester, const ExploreScreen());
    Focus.of(tester.element(find.text('Home'))).requestFocus();
    await tester.pump();
    expect(_focusedLabel(), 'Home');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(_focusedLabel(), 'Discover');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(_focusedLabel(), 'Requests');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(_focusedLabel(), 'Home');

    await tester.pumpWidget(const SizedBox());
    await _pump(tester, const ExploreRequestsScreen());
    Focus.of(tester.element(find.text('Home'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(_focusedLabel(), 'Requests');
    // Then straight down into the filter pills (whichever sits below the tab).
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      SeerrRequestFilter.values.map((f) => f.label),
      contains(_focusedLabel()),
    );
  });

  testWidgets('Explore shows requests and discovery rails', (tester) async {
    await _pump(tester, const ExploreScreen());
    expect(find.byType(PageScaffold), findsOneWidget);
    expect(find.text('Your Requests'), findsOneWidget);
    expect(find.text('Trending'), findsOneWidget);
    expect(find.text('Popular Movies'), findsOneWidget);
    expect(find.text('Popular Shows'), findsOneWidget);
    expect(find.text('Coming Soon'), findsOneWidget);
    expect(find.byType(SeerrCard), findsWidgets);
    // Library and on-the-way titles carry a badge, the rest don't.
    expect(find.byType(SeerrStatusBadge), findsWidgets);
    expect(find.byType(SeerrNotLinkedNote), findsNothing);
  });

  testWidgets('Explore search lists titles and people', (tester) async {
    await _pump(tester, const ExploreScreen(initialQuery: 'the'));
    expect(find.text('Movies & Shows'), findsOneWidget);
    expect(find.text('The Kid'), findsOneWidget);
    expect(find.text('Trending'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await _pump(tester, const ExploreScreen(initialQuery: 'keaton'));
    expect(find.text('People'), findsOneWidget);
    expect(find.text('Buster Keaton'), findsOneWidget);
  });

  testWidgets('without a linked account Explore browses only', (tester) async {
    await _pump(tester, const ExploreScreen(), seerr: MockSeerr(user: null));
    expect(find.byType(SeerrNotLinkedNote), findsOneWidget);
    expect(find.text('Your Requests'), findsNothing);
    expect(find.text('Trending'), findsOneWidget);
  });

  testWidgets('Explore explains when Seerr is unreachable', (tester) async {
    await _pump(tester, const ExploreScreen(), seerr: _DownSeerr());
    expect(find.text("Can't reach Seerr"), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('a movie title page requests, then shows it as requested', (
    tester,
  ) async {
    final seerr = MockSeerr();
    await _pump(
      tester,
      const ExploreTitleScreen(mediaType: SeerrMediaType.movie, tmdbId: 104),
      seerr: seerr,
    );
    expect(find.text('The Kid'), findsOneWidget);
    expect(find.text('Watch in Soup'), findsNothing);
    expect(find.byType(SeerrStatusPill), findsNothing);
    await _tapButton(tester, 'Request');
    expect(find.text('Request'), findsNothing);
    expect(find.text('Requested'), findsOneWidget);
    // The mock answers after a delay, which needs real time.
    final page = await tester.runAsync(
      () => seerr.myRequests(SeerrRequestFilter.pending),
    );
    expect(page!.requests.map((r) => r.tmdbId), contains(104));
  });

  testWidgets('a show with open seasons opens the season picker', (
    tester,
  ) async {
    await _pump(
      tester,
      const ExploreTitleScreen(mediaType: SeerrMediaType.tv, tmdbId: 203),
    );
    expect(find.text('The Gold Rush'), findsOneWidget);
    expect(find.byType(SeasonPicker), findsNothing);
    await _tapButton(tester, 'Request seasons');
    expect(find.byType(SeasonPicker), findsOneWidget);
    expect(find.text('Request all seasons'), findsOneWidget);
    // Dropping one season changes the button to a count.
    await tester.tap(
      find.descendant(
        of: find.byType(SeasonPicker),
        matching: find.text('Season 4'),
      ),
    );
    await tester.pump();
    expect(find.text('Request 3 seasons'), findsOneWidget);
    await tester.tap(find.text('Request 3 seasons'));
    await _settle(tester);
    expect(find.byType(SeasonPicker), findsNothing);
    expect(find.text('Requested'), findsWidgets);
  });

  testWidgets('a library title offers Watch in Soup, not Request', (
    tester,
  ) async {
    await _pump(
      tester,
      const ExploreTitleScreen(mediaType: SeerrMediaType.movie, tmdbId: 101),
    );
    expect(find.text('Metropolis'), findsOneWidget);
    expect(find.text('Watch in Soup'), findsOneWidget);
    expect(find.text('Request'), findsNothing);
    expect(find.text('In your library'), findsOneWidget);
  });

  testWidgets('Requests lists and withdraws', (tester) async {
    await _pump(tester, const ExploreRequestsScreen());
    expect(find.byType(SeerrRequestCard), findsNWidgets(3));
    expect(find.text('Night of the Living Dead'), findsOneWidget);
    expect(find.text('Withdraw'), findsOneWidget);
    await tester.tap(find.text('Withdraw'));
    await _settle(tester);
    expect(find.byType(SeerrRequestCard), findsNWidgets(2));
    expect(find.text('Night of the Living Dead'), findsNothing);
  });

  testWidgets('touch Explore fits a phone with an Explore tab', (tester) async {
    await _pump(tester, const ExploreScreen(), touch: true);
    expect(find.byType(TouchScaffold), findsOneWidget);
    expect(find.text('Explore'), findsWidgets);
    expect(find.text('Trending'), findsOneWidget);
    expect(find.text('Your Requests'), findsOneWidget);
  });

  testWidgets('touch title page requests from the summary', (tester) async {
    await _pump(
      tester,
      const ExploreTitleScreen(mediaType: SeerrMediaType.movie, tmdbId: 106),
      touch: true,
    );
    expect(find.text('Charade'), findsOneWidget);
    await tester.tap(find.text('Request'));
    await _settle(tester);
    expect(find.text('Requested'), findsOneWidget);
  });

  testWidgets('touch Requests page fits a phone', (tester) async {
    await _pump(tester, const ExploreRequestsScreen(), touch: true);
    expect(find.byType(SeerrRequestCard), findsNWidgets(3));
    expect(find.text('Withdraw'), findsOneWidget);
  });
}

/// The text inside whatever has focus.
String? _focusedLabel() {
  String? label;
  void visit(Element e) {
    if (label != null) return;
    final w = e.widget;
    if (w is Text) {
      label = w.data;
    } else {
      e.visitChildren(visit);
    }
  }

  (FocusManager.instance.primaryFocus?.context as Element?)?.visitChildren(
    visit,
  );
  return label;
}

/// Seerr with no server configured on the plugin side.
class _UnconfiguredSeerr extends MockSeerr {
  @override
  Future<SeerrStatus> fetchStatus() async =>
      const SeerrStatus(configured: false, reachable: false);
}

/// Seerr configured but not answering.
class _DownSeerr extends MockSeerr {
  @override
  Future<SeerrStatus> fetchStatus() async => const SeerrStatus(
    configured: true,
    reachable: false,
    error: 'connection refused',
  );
}

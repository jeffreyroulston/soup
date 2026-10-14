import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soup_v2/src/app_scope.dart';
import 'package:soup_v2/src/data/mock_catalog.dart';
import 'package:soup_v2/src/data/models.dart';
import 'package:soup_v2/src/data/playback_prefs.dart';
import 'package:soup_v2/src/features/favourites/favourites_screen.dart';
import 'package:soup_v2/src/features/home/home_screen.dart';
import 'package:soup_v2/src/mock_app.dart';
import 'package:soup_v2/src/features/item/item_screen.dart';
import 'package:soup_v2/src/features/library/library_screen.dart';
import 'package:soup_v2/src/features/settings/settings_screen.dart';
import 'package:soup_v2/src/ui/theme/soup_theme.dart';
import 'package:soup_v2/src/features/library/library_filter.dart';
import 'package:soup_v2/src/ui/widgets/glass_nav.dart';
import 'package:soup_v2/src/ui/widgets/media_card.dart';
import 'package:soup_v2/src/ui/widgets/pill_tabs.dart';
import 'package:soup_v2/src/utils/media.dart';

Widget _app(Widget home) {
  final catalog = MockCatalog();
  final prefs = PlaybackPrefs();
  return MaterialApp(
    theme: SoupTheme.dark,
    builder: (context, child) => SoupScope(
      catalog: catalog,
      prefs: prefs,
      userLabel: 'mock@soup.dev',
      onSignOut: () async {},
      child: child!,
    ),
    home: home,
  );
}

Future<void> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(1440, 810);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(home));
  // Mock artwork renders through dart:ui, which needs real async.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 200)),
  );
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('home shows hero, rows and nav', (tester) async {
    await _pump(tester, const HomeScreen());
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Keep Watching'), findsOneWidget);
    expect(find.text('Recently Added'), findsOneWidget);
    // The hero's Resume button carries the time left beside its label.
    expect(find.text('Resume'), findsWidgets);
    expect(find.text('1 hr left'), findsWidgets);
  });

  testWidgets('an arrow with no focus starts from the nav', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MockApp());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 300));
    final focused = FocusManager.instance.primaryFocus?.context;
    expect(focused?.findAncestorWidgetOfExactType<GlassNav>(), isNotNull);
  });

  testWidgets('library filters narrow the grid', (tester) async {
    final catalog = MockCatalog();
    final lib = (await catalog.libraries()).first;
    await _pump(tester, LibraryScreen(library: lib));
    expect(find.text('16 titles'), findsOneWidget);
    // The filter pill, not the nav's Favourites tab.
    await tester.tap(
      find.descendant(
        of: find.byType(PillTabs<LibraryFilter>),
        matching: find.text('Favourites'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Nothing matches these filters.'), findsOneWidget);
  });

  testWidgets('library cards fill the row up to the A–Z strip', (tester) async {
    final lib = (await MockCatalog().libraries()).first;
    await _pump(tester, LibraryScreen(library: lib));
    final rects = find
        .byType(MediaCard)
        .evaluate()
        .map((e) => tester.getRect(find.byWidget(e.widget)));
    final firstRow = rects.where((r) => r.top == rects.first.top).toList();
    expect(firstRow.first.left, 56);
    // 1440 wide, minus the strip's 80: no ragged gap on the right.
    expect(firstRow.last.right, closeTo(1360, 0.5));
  });

  testWidgets('A–Z strip: Right enters at the card letter, ends hold, '
      'Left returns to that letter', (tester) async {
    final lib = (await MockCatalog().libraries()).first;
    await _pump(tester, LibraryScreen(library: lib));
    String? focused() => FocusManager.instance.primaryFocus?.debugLabel;
    CatalogItem? focusedItem() => FocusManager.instance.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<MediaCard>()
        ?.item;

    // Walk to the end of the first row, then step onto the strip.
    CatalogItem? last;
    for (var i = 0; i < 12 && focused()?.startsWith('letter ') != true; i++) {
      last = focusedItem() ?? last;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
    }
    expect(focused(), 'letter ${sortLetter(last!)}');

    // Up past the first letter stays on the strip.
    for (var i = 0; i < 30; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
    }
    expect(focused(), startsWith('letter '));
    final letter = focused()!.substring('letter '.length);

    // Left goes into the grid at that letter's first title.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(focused(), 'letter target');
    expect(sortLetter(focusedItem()!), letter);
  });

  testWidgets('item screen shows series seasons and episodes', (tester) async {
    await _pump(tester, const ItemScreen(itemId: 's2'));
    expect(find.text('After Kitchen'), findsWidgets);
    expect(find.text('Season 1'), findsWidgets);
    expect(find.textContaining('of 4 watched'), findsOneWidget);
  });

  testWidgets('episode screen leads with the episode, not the show', (
    tester,
  ) async {
    await _pump(tester, const ItemScreen(itemId: 's2-s1e3'));
    expect(find.text('SEASON 1 · EPISODE 3'), findsOneWidget);
    expect(find.text('Episode title 3'), findsWidgets);
    expect(find.text('PREVIOUS · E2'), findsOneWidget);
    expect(find.text('NEXT · E4'), findsOneWidget);
    expect(find.text('FROM THE SHOW'), findsOneWidget);
    expect(find.text('Cast & Crew'), findsNothing);
    expect(find.text('Related'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings toggles persist into prefs', (tester) async {
    await _pump(tester, const SettingsScreen());
    expect(find.text('Autoplay next episode'), findsOneWidget);
    await tester.tap(find.text('Skip intros and recaps'));
    await tester.pump();
    final scope = SoupScope.of(tester.element(find.byType(SettingsScreen)));
    expect(scope.prefs.autoSkipIntros, isTrue);
  });

  testWidgets('favourites: type pills count, un-hearting drops the title', (
    tester,
  ) async {
    await _pump(tester, const FavouritesScreen());
    expect(find.text('No favourites yet'), findsOneWidget);
    final catalog = SoupScope.of(
      tester.element(find.byType(FavouritesScreen)),
    ).catalog;
    await catalog.setFavorite('m1', true);
    await catalog.setFavorite('s2', true);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('2 titles'), findsOneWidget);
    expect(find.text('Movies  1'), findsOneWidget);
    expect(find.text('Shows  1'), findsOneWidget);
    // No favourite episodes, so no Episodes pill.
    expect(find.textContaining('Episodes'), findsNothing);

    await tester.tap(find.text('Movies  1'));
    await tester.pump();
    expect(find.text('Northlight'), findsOneWidget);
    expect(find.text('After Kitchen'), findsNothing);

    // The last movie going sends the page back to All.
    await catalog.setFavorite('m1', false);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('1 title'), findsOneWidget);
    expect(find.text('After Kitchen'), findsOneWidget);
  });

  testWidgets('item More menu toggles the favourite', (tester) async {
    await _pump(tester, const ItemScreen(itemId: 'm1'));
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Mark as watched'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to Favourites'));
    await tester.pumpAndSettle();
    final catalog = SoupScope.of(
      tester.element(find.byType(ItemScreen)),
    ).catalog;
    expect(catalog.isFavorite(await catalog.item('m1')), isTrue);
    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Remove from Favourites'), findsOneWidget);
  });
}

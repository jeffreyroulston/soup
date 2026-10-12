import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soup_v2/src/app_scope.dart';
import 'package:soup_v2/src/data/mock_catalog.dart';
import 'package:soup_v2/src/data/models.dart';
import 'package:soup_v2/src/data/playback_prefs.dart';
import 'package:soup_v2/src/features/home/home_screen.dart';
import 'package:soup_v2/src/features/item/item_screen.dart';
import 'package:soup_v2/src/features/library/library_screen.dart';
import 'package:soup_v2/src/features/settings/settings_screen.dart';
import 'package:soup_v2/src/ui/theme/soup_theme.dart';
import 'package:soup_v2/src/ui/widgets/media_card.dart';
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
    expect(find.text('Resume · 1 hr'), findsOneWidget);
  });

  testWidgets('library filters narrow the grid', (tester) async {
    final catalog = MockCatalog();
    final lib = (await catalog.libraries()).first;
    await _pump(tester, LibraryScreen(library: lib));
    expect(find.text('16 titles'), findsOneWidget);
    await tester.tap(find.text('Favourites'));
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

  testWidgets('settings toggles persist into prefs', (tester) async {
    await _pump(tester, const SettingsScreen());
    expect(find.text('Autoplay next episode'), findsOneWidget);
    await tester.tap(find.text('Skip intros and recaps'));
    await tester.pump();
    final scope = SoupScope.of(tester.element(find.byType(SettingsScreen)));
    expect(scope.prefs.autoSkipIntros, isTrue);
  });
}

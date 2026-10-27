import 'dart:async';

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

/// A library big enough to scroll: a dozen titles under every letter.
class _BigLibraryCatalog extends MockCatalog {
  @override
  Future<List<CatalogItem>> libraryItems(
    CatalogItem library,
    LibrarySort sort,
  ) async => [
    for (var l = 0; l < 26; l++)
      for (var i = 0; i < 12; i++)
        CatalogItem(
          id: 'big-$l-$i',
          name: '${String.fromCharCode(65 + l)} title $i',
          type: 'Movie',
        ),
  ];
}

Widget _app(Widget home, {MockCatalog? catalog}) {
  final scopeCatalog = catalog ?? MockCatalog();
  final prefs = PlaybackPrefs();
  return MaterialApp(
    theme: SoupTheme.dark,
    builder: (context, child) => SoupScope(
      catalog: scopeCatalog,
      prefs: prefs,
      userLabel: 'mock@soup.dev',
      onSignOut: () async {},
      child: child!,
    ),
    home: home,
  );
}

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  MockCatalog? catalog,
}) async {
  tester.view.physicalSize = const Size(1440, 810);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(home, catalog: catalog));
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

  testWidgets('holding Down outruns the scroll without snapping to the nav', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MockApp());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    bool inNav() =>
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<GlassNav>() !=
        null;

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 40));
    var left = !inNav();
    for (var i = 0; i < 40; i++) {
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 40));
      if (!inNav()) left = true;
      if (left) expect(inNav(), isFalse, reason: 'snapped back at repeat $i');
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 400));
    expect(left, isTrue);
    expect(inNav(), isFalse);
  });

  testWidgets('nav tabs open pages with the bar in place and focus kept', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MockApp());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    String? focusedLabel() {
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

    // Home opens on the hero; Back moves up to the bar.
    final dynamic app = tester.state(find.byType(WidgetsApp));
    await app.didPopRoute();
    await tester.pump(const Duration(milliseconds: 300));
    expect(focusedLabel(), 'Home');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(focusedLabel(), 'Movies');

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    // The new page's bar has its library tabs on the first frame, and focus
    // is already on its Movies tab.
    await tester.pump(); // the pushed page's first frame
    final libraryNav = find.descendant(
      of: find.byType(LibraryScreen),
      matching: find.byType(GlassNav),
    );
    expect(
      find.descendant(of: libraryNav, matching: find.text('Movies')),
      findsOneWidget,
    );
    expect(focusedLabel(), 'Movies');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // Loading the grid doesn't pull focus into the content.
    expect(focusedLabel(), 'Movies');
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<LibraryScreen>(),
      isNotNull,
    );

    // Back from the bar goes Home and lands on its Home tab.
    await app.didPopRoute();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(LibraryScreen), findsNothing);
    expect(focusedLabel(), 'Home');
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
      'browsing holds the grid, OK jumps to the letter', (tester) async {
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

    // Moving along the strip only moves focus; the grid stays put.
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    final before = scrollable.position.pixels;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 300));
    expect(scrollable.position.pixels, before);
    final letter = focused()!.substring('letter '.length);

    // OK goes straight into the grid at that letter's first title.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();
    expect(focused(), 'letter target');
    expect(sortLetter(focusedItem()!), letter);
  });

  testWidgets('A–Z strip: Left returns to the card it was entered from, '
      'after jumping down the grid', (tester) async {
    final catalog = _BigLibraryCatalog();
    final lib = (await catalog.libraries()).first;
    await _pump(tester, LibraryScreen(library: lib), catalog: catalog);
    String? focused() => FocusManager.instance.primaryFocus?.debugLabel;
    bool onStrip() => RegExp(r'^letter .$').hasMatch(focused() ?? '');
    CatalogItem? focusedItem() => FocusManager.instance.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<MediaCard>()
        ?.item;
    Future<void> rightToStrip() async {
      for (var i = 0; i < 12 && !onStrip(); i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
      }
    }

    // Onto the strip, down to a later letter, OK to jump the grid there.
    await rightToStrip();
    for (var i = 0; i < 14; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    // Back onto the strip from the end of that row, then down the strip.
    CatalogItem? from;
    for (var i = 0; i < 12 && !onStrip(); i++) {
      from = focusedItem() ?? from;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
    }
    expect(onStrip(), isTrue);
    for (var i = 0; i < 6; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
    }

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(focusedItem()?.id, from!.id);
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

  testWidgets('watched toggles at once; quick presses settle in order', (
    tester,
  ) async {
    final catalog = _SlowPlayedCatalog();
    await _pump(tester, const ItemScreen(itemId: 'm1'), catalog: catalog);
    await tester.tap(find.text('Mark as watched'));
    await tester.pump();
    expect(find.text('Watched'), findsOneWidget);
    // Pressed again while the first write is still out.
    await tester.tap(find.text('Watched'));
    await tester.pump();
    expect(find.text('Mark as watched'), findsOneWidget);
    expect(catalog.writes, [true]);
    catalog.release();
    await tester.pump();
    expect(catalog.writes, [true, false]);
    catalog.release();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Mark as watched'), findsOneWidget);
    expect((await catalog.item('m1')).played, isFalse);
  });

  testWidgets('a failed watched write reverts the toggle', (tester) async {
    final catalog = _SlowPlayedCatalog();
    await _pump(tester, const ItemScreen(itemId: 'm1'), catalog: catalog);
    await tester.tap(find.text('Mark as watched'));
    await tester.pump();
    expect(find.text('Watched'), findsOneWidget);
    catalog.release(fail: true);
    await tester.pump();
    await tester.pump();
    expect(find.text('Mark as watched'), findsOneWidget);
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

/// Holds each watched write until [release], to see the UI before the server
/// answers.
class _SlowPlayedCatalog extends MockCatalog {
  final writes = <bool>[];
  final _gates = <Completer<void>>[];

  @override
  Future<void> setPlayed(String itemId, bool value) async {
    writes.add(value);
    final gate = Completer<void>();
    _gates.add(gate);
    await gate.future;
    await super.setPlayed(itemId, value);
  }

  void release({bool fail = false}) {
    final gate = _gates.removeAt(0);
    fail ? gate.completeError(StateError('offline')) : gate.complete();
  }
}

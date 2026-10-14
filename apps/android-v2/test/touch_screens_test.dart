import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soup_v2/src/app_scope.dart';
import 'package:soup_v2/src/data/mock_catalog.dart';
import 'package:soup_v2/src/data/playback_prefs.dart';
import 'package:soup_v2/src/features/collection/collection_screen.dart';
import 'package:soup_v2/src/features/home/home_screen.dart';
import 'package:soup_v2/src/features/item/item_screen.dart';
import 'package:soup_v2/src/features/library/library_filter.dart';
import 'package:soup_v2/src/features/library/library_screen.dart';
import 'package:soup_v2/src/features/search/search_screen.dart';
import 'package:soup_v2/src/features/settings/settings_screen.dart';
import 'package:soup_v2/src/form_factor.dart';
import 'package:soup_v2/src/ui/theme/soup_theme.dart';
import 'package:soup_v2/src/ui/touch/touch_frame.dart';
import 'package:soup_v2/src/ui/touch/touch_scaffold.dart';
import 'package:soup_v2/src/ui/widgets/pill_tabs.dart';

/// The touch UI on a phone-sized screen (Pixel 7: 412×915 dp).
Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  Size size = const Size(412, 915),
}) async {
  tester.view.physicalSize = size * 2.625;
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  final catalog = MockCatalog();
  final prefs = PlaybackPrefs();
  await tester.pumpWidget(
    MaterialApp(
      theme: SoupTheme.dark,
      builder: (context, child) => FormFactorScope(
        value: FormFactor.touch,
        child: TouchFrame(
          child: SoupScope(
            catalog: catalog,
            prefs: prefs,
            userLabel: 'mock@soup.dev',
            onSignOut: () async {},
            child: child!,
          ),
        ),
      ),
      home: home,
    ),
  );
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 200)),
  );
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('home uses the touch shell with a bottom nav', (tester) async {
    await _pump(tester, const HomeScreen());
    expect(find.byType(TouchScaffold), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Keep Watching'), findsOneWidget);
    expect(find.text('Resume'), findsWidgets);
  });

  testWidgets('library filters narrow the touch grid', (tester) async {
    final lib = (await MockCatalog().libraries()).first;
    await _pump(tester, LibraryScreen(library: lib));
    expect(find.text('16 titles'), findsOneWidget);
    // The filter pill, not the bottom nav's Favourites tab.
    final pill = find.descendant(
      of: find.byType(PillTabs<LibraryFilter>),
      matching: find.text('Favourites'),
    );
    await tester.ensureVisible(pill);
    await tester.tap(pill);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Nothing matches these filters.'), findsOneWidget);
  });

  testWidgets('series item lists episodes vertically', (tester) async {
    await _pump(tester, const ItemScreen(itemId: 's2'));
    expect(find.text('After Kitchen'), findsWidgets);
    expect(find.textContaining('of 4 watched'), findsOneWidget);
    expect(find.text('Episodes'), findsOneWidget);
  });

  testWidgets('episode item fits a phone', (tester) async {
    await _pump(tester, const ItemScreen(itemId: 's2-s1e3'));
    expect(find.text('SEASON 1 · EPISODE 3'), findsOneWidget);
    expect(find.text('NEXT · E4'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('select menus open as a bottom sheet', (tester) async {
    final lib = (await MockCatalog().libraries()).first;
    await _pump(tester, LibraryScreen(library: lib));
    await tester.tap(find.text('Title'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.tap(find.text('Year'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Year'), findsOneWidget);
  });

  testWidgets('search, collection and settings fit a phone', (tester) async {
    await _pump(tester, const SearchScreen());
    expect(find.text('BROWSE'), findsOneWidget);
    await _pump(tester, const CollectionScreen(packId: 'missing'));
    expect(find.textContaining("isn't available"), findsOneWidget);
    await _pump(tester, const SettingsScreen());
    expect(find.text('Autoplay next episode'), findsOneWidget);
  });

  testWidgets('touch screens also fit a landscape tablet', (tester) async {
    await _pump(tester, const HomeScreen(), size: const Size(1280, 800));
    expect(find.text('Keep Watching'), findsOneWidget);
    await _pump(
      tester,
      const ItemScreen(itemId: 's2'),
      size: const Size(1280, 800),
    );
    expect(find.text('Episodes'), findsOneWidget);
  });
}

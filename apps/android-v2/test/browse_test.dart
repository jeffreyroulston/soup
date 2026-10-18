import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soup_v2/src/app_scope.dart';
import 'package:soup_v2/src/data/mock_catalog.dart';
import 'package:soup_v2/src/data/models.dart';
import 'package:soup_v2/src/data/playback_prefs.dart';
import 'package:soup_v2/src/features/item/item_screen.dart';
import 'package:soup_v2/src/features/library/library_screen.dart';
import 'package:soup_v2/src/ui/theme/soup_theme.dart';
import 'package:soup_v2/src/ui/widgets/media_card.dart';
import 'package:soup_v2/src/ui/widgets/select_menu.dart';

final _navigator = GlobalKey<NavigatorState>();

Future<void> _pump(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(1440, 810);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final catalog = MockCatalog();
  addTearDown(catalog.dispose);
  final prefs = PlaybackPrefs();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: _navigator,
      theme: SoupTheme.dark,
      builder: (context, child) => SoupScope(
        catalog: catalog,
        prefs: prefs,
        onSignOut: () async {},
        child: child!,
      ),
      home: const Scaffold(body: Text('root')),
    ),
  );
  _navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => page));
  await _settle(tester);
}

/// Mock artwork renders through dart:ui, which needs real async.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 200)),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

bool _hasAzStrip(WidgetTester tester) => find
    .byWidgetPredicate((w) => w.runtimeType.toString() == '_AzStrip')
    .evaluate()
    .isNotEmpty;

void main() {
  testWidgets('Next episode replaces the page instead of stacking one', (
    tester,
  ) async {
    await _pump(tester, const ItemScreen(itemId: 's2-s1e3'));
    await tester.tap(find.text('NEXT · E4'));
    await _settle(tester);
    expect(find.text('SEASON 1 · EPISODE 4'), findsOneWidget);

    _navigator.currentState!.pop();
    await _settle(tester);
    expect(find.text('root'), findsOneWidget);
  });

  testWidgets('the A–Z strip shows only in title order', (tester) async {
    final lib = (await MockCatalog().libraries()).first;
    await _pump(tester, LibraryScreen(library: lib));
    expect(_hasAzStrip(tester), isTrue);

    await tester.tap(find.byType(SelectMenu<LibrarySort>));
    await _settle(tester);
    await tester.tap(find.text('Year').last);
    await _settle(tester);
    expect(_hasAzStrip(tester), isFalse);
  });

  testWidgets('a card announces its title and details as a button', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      const Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: MediaCard(
            width: 200,
            item: CatalogItem(
              id: 'm',
              name: 'Northlight',
              type: 'Movie',
              productionYear: 2023,
              played: true,
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Northlight, 2023, watched')),
      isSemantics(
        label: 'Northlight, 2023, watched',
        isButton: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });
}

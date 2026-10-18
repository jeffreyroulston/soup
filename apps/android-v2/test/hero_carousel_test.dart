import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soup_v2/src/app_scope.dart';
import 'package:soup_v2/src/data/mock_catalog.dart';
import 'package:soup_v2/src/data/models.dart';
import 'package:soup_v2/src/data/playback_prefs.dart';
import 'package:soup_v2/src/ui/widgets/hero_carousel.dart';

const _slides = [
  HeroSlide(CatalogItem(id: 'a', name: 'A', type: 'Movie')),
  HeroSlide(CatalogItem(id: 'b', name: 'B', type: 'Movie')),
  HeroSlide(CatalogItem(id: 'c', name: 'C', type: 'Movie')),
];

void main() {
  final navigator = GlobalKey<NavigatorState>();

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 810);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final catalog = MockCatalog();
    addTearDown(catalog.dispose);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        builder: (context, child) => SoupScope(
          catalog: catalog,
          prefs: PlaybackPrefs(),
          onSignOut: () async {},
          child: child!,
        ),
        home: const Scaffold(body: HeroCarousel(slides: _slides)),
      ),
    );
    // The carousel holds while it has focus; these tests watch it advance.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
  }

  bool built(String id) =>
      find.byKey(ValueKey(id), skipOffstage: false).evaluate().isNotEmpty;

  testWidgets('only the showing slide is built, plus one fading out', (
    tester,
  ) async {
    await pump(tester);
    expect([built('a'), built('b'), built('c')], [true, false, false]);

    await tester.pump(const Duration(seconds: 8));
    await tester.pump(const Duration(milliseconds: 300));
    expect([built('a'), built('b'), built('c')], [true, true, false]);

    await tester.pump(const Duration(seconds: 1));
    expect([built('a'), built('b'), built('c')], [false, true, false]);
  });

  testWidgets('a covered carousel holds its slide', (tester) async {
    await pump(tester);
    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Scaffold()),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 17));
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(built('a'), isTrue);
    expect(built('b') || built('c'), isFalse);
  });
}

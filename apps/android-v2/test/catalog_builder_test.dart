import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soup_v2/src/app_scope.dart';
import 'package:soup_v2/src/data/mock_catalog.dart';
import 'package:soup_v2/src/data/playback_prefs.dart';
import 'package:soup_v2/src/ui/widgets/catalog_builder.dart';

void main() {
  late MockCatalog catalog;
  late Map<String, int> loads;
  final navigator = GlobalKey<NavigatorState>();

  Widget counting(String name, {List<Object?> keys = const []}) =>
      CatalogBuilder<String>(
        keys: keys,
        load: (_) async {
          loads[name] = (loads[name] ?? 0) + 1;
          if (keys.firstOrNull == 'fail') throw StateError('failed');
          return name;
        },
        builder: (_, data, error) =>
            Text(error != null ? 'error' : data ?? 'loading'),
      );

  Future<void> pumpApp(WidgetTester tester, Widget home) async {
    catalog = MockCatalog();
    addTearDown(catalog.dispose);
    loads = {};
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        builder: (context, child) => SoupScope(
          catalog: catalog,
          prefs: PlaybackPrefs(),
          onSignOut: () async {},
          child: child!,
        ),
        home: Scaffold(body: home),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a covered page reloads when shown again, not on every change', (
    tester,
  ) async {
    await pumpApp(tester, counting('below'));
    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => Scaffold(body: counting('top'))),
    );
    await tester.pumpAndSettle();
    expect(loads, {'below': 1, 'top': 1});

    catalog.refresh();
    catalog.refresh();
    await tester.pumpAndSettle();
    expect(loads, {'below': 1, 'top': 3});

    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(loads, {'below': 2, 'top': 3});
  });

  testWidgets('changing keys clears the previous error', (tester) async {
    Widget page(String key) => counting('page', keys: [key]);
    await pumpApp(tester, page('fail'));
    expect(find.text('error'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        builder: (context, child) => SoupScope(
          catalog: catalog,
          prefs: PlaybackPrefs(),
          onSignOut: () async {},
          child: child!,
        ),
        home: Scaffold(body: page('ok')),
      ),
    );
    // Before the new load lands, the stale error is gone.
    expect(find.text('loading'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('page'), findsOneWidget);
  });
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soup_v2/src/app_scope.dart';
import 'package:soup_v2/src/data/mock_catalog.dart';
import 'package:soup_v2/src/data/playback_prefs.dart';
import 'package:soup_v2/src/ui/theme/soup_theme.dart';
import 'package:soup_v2/src/ui/widgets/user_avatar.dart';

// 1x1 transparent PNG.
final _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

class _AvatarCatalog extends MockCatalog {
  _AvatarCatalog(this._bytes);

  Uint8List? _bytes;
  int _rev = 0;

  @override
  int get revision => _rev;

  @override
  Future<Uint8List?> userAvatar({int maxWidth = 256}) async => _bytes;

  void updateAvatar(Uint8List? next) {
    _bytes = next;
    _rev++;
    notifyListeners();
  }
}

Widget _wrap(_AvatarCatalog catalog, Widget child) {
  final prefs = PlaybackPrefs();
  return MaterialApp(
    theme: SoupTheme.dark,
    home: SoupScope(
      catalog: catalog,
      prefs: prefs,
      userLabel: 'Alex',
      onSignOut: () async {},
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  testWidgets('UserAvatar renders Jellyfin bytes when available', (
    tester,
  ) async {
    final catalog = _AvatarCatalog(_pngBytes);
    addTearDown(catalog.dispose);
    await tester.pumpWidget(_wrap(catalog, const UserAvatar(label: 'Alex')));
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('A'), findsNothing);
  });

  testWidgets('UserAvatar falls back to initial or custom fallback when null', (
    tester,
  ) async {
    final catalog = _AvatarCatalog(null);
    addTearDown(catalog.dispose);
    await tester.pumpWidget(_wrap(catalog, const UserAvatar(label: 'Alex')));
    await tester.pump();

    expect(find.byType(Image), findsNothing);
    expect(find.text('A'), findsOneWidget);

    await tester.pumpWidget(
      _wrap(
        catalog,
        const UserAvatar(
          label: 'Alex',
          size: 24,
          fallback: Icon(Icons.person_outline_rounded),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);
  });

  testWidgets('UserAvatar updates when catalog refreshes', (tester) async {
    final catalog = _AvatarCatalog(null);
    addTearDown(catalog.dispose);
    await tester.pumpWidget(_wrap(catalog, const UserAvatar(label: 'Alex')));
    await tester.pump();
    expect(find.text('A'), findsOneWidget);

    catalog.updateAvatar(_pngBytes);
    await tester.pump();
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
  });
}

import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'data/mock_catalog.dart';
import 'data/playback_prefs.dart';
import 'features/home/home_screen.dart';
import 'ui/theme/soup_theme.dart';
import 'ui/widgets/design_scale.dart';

/// `--dart-define=SOUP_MOCK=true`: the full UI over [MockCatalog], with no
/// Tailscale, identity or Jellyfin server.
class MockApp extends StatefulWidget {
  const MockApp({super.key});

  @override
  State<MockApp> createState() => _MockAppState();
}

class _MockAppState extends State<MockApp> {
  final _catalog = MockCatalog();
  final _prefs = PlaybackPrefs()..load();

  @override
  void dispose() {
    _catalog.dispose();
    _prefs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Soup (mock)',
    debugShowCheckedModeBanner: false,
    theme: SoupTheme.dark,
    builder: (context, child) => DesignScale(
      child: SoupScope(
        catalog: _catalog,
        prefs: _prefs,
        userLabel: 'mock@soup.dev',
        onSignOut: () async {},
        child: child!,
      ),
    ),
    home: const HomeScreen(),
  );
}

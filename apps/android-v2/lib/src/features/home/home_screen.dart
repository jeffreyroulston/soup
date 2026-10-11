import 'package:flutter/material.dart';
import 'package:soup_core/soup_core.dart';

import '../../ui/theme/soup_tokens.dart';
import '../../ui/widgets/soup_button.dart';

/// Placeholder until the web-style home (hero + rails) lands.
class HomeScreen extends StatelessWidget {
  const HomeScreen({required this.session, required this.onSignOut, super.key});

  final JellyfinSession session;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('soup', style: SoupType.style(size: 56, weight: 800, letterSpacing: -2)),
          const SizedBox(height: 16),
          Text('Signed in', style: SoupType.style(size: 22, color: SoupColors.muted)),
          const SizedBox(height: 28),
          SoupButton(label: 'Sign out', onPressed: onSignOut, autofocus: true),
        ],
      ),
    ),
  );
}

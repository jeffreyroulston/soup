import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soup_v2/src/ui/theme/soup_theme.dart';
import 'package:soup_v2/src/ui/theme/soup_tokens.dart';
import 'package:soup_v2/src/ui/widgets/focusable.dart';
import 'package:soup_v2/src/ui/widgets/soup_button.dart';

void main() {
  test('tokens match the web design system', () {
    expect(SoupColors.canvas, const Color(0xFF0A0A0B));
    expect(SoupColors.accent, const Color(0xFFFC7814));
    expect(SoupTheme.dark.scaffoldBackgroundColor, SoupColors.canvas);
  });

  testWidgets('SoupButton activates on select and shows focus ring', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: SoupTheme.dark,
        home: Scaffold(
          body: Center(
            child: SoupButton(
              label: 'Play',
              autofocus: true,
              onPressed: () => taps++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Focusable), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(taps, 1);
  });
}

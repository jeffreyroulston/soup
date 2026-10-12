import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soup/src/features/appearance/soup_theme.dart';
import 'package:soup/src/features/shared/soup_mark.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('native launcher background matches the onboarding canvas', () async {
    final xml = await File(
      'android/app/src/main/res/values/colors.xml',
    ).readAsString();
    final value = RegExp(
      r'<color name="soup_icon_background">#([A-Fa-f0-9]{6})</color>',
    ).firstMatch(xml)?.group(1);
    expect(value, isNotNull);
    expect(
      Color(int.parse('FF$value', radix: 16)),
      SoupTheme.onboardingBackground,
    );
  });

  test('native editor text retains contrast on its light canvas', () async {
    final xml = await File(
      'android/app/src/main/res/values/styles.xml',
    ).readAsString();
    final style = RegExp(
      r'<style name="TvTextInputTheme"[\s\S]*?</style>',
    ).firstMatch(xml)!.group(0)!;
    final background = SoupTheme.onboardingBackground.computeLuminance();
    for (final attribute in [
      'textColorPrimary',
      'textColorSecondary',
      'textColorHint',
    ]) {
      final hex = RegExp(
        '<item name="android:$attribute">#([A-Fa-f0-9]{6})</item>',
      ).firstMatch(style)?.group(1);
      expect(
        hex,
        isNotNull,
        reason: 'TV theme defaults can supply white text on a light canvas',
      );
      final foreground = Color(
        int.parse('FF$hex', radix: 16),
      ).computeLuminance();
      expect(
        (background + 0.05) / (foreground + 0.05),
        greaterThanOrEqualTo(4.5),
        reason: attribute,
      );
    }
  });

  Future<(int, int, int Function(int, int))> decode(List<int> bytes) async {
    final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final pixels = (await image.toByteData())!;
    final width = image.width;
    final height = image.height;
    image.dispose();
    codec.dispose();
    return (
      width,
      height,
      (int x, int y) => pixels.getUint8((y * width + x) * 4 + 3),
    );
  }

  test('Flutter mark is the rounded fill-line icon tile', () async {
    final data = await rootBundle.load(SoupMark.assetName);
    final (width, height, alpha) = await decode(data.buffer.asUint8List());
    expect(width, height);
    expect(width, greaterThanOrEqualTo(1024));
    expect(alpha(0, 0), 0, reason: 'Corners are rounded off');
    expect(alpha(width ~/ 2, 0), 255, reason: 'The tile reaches each edge');
    expect(alpha(width ~/ 2, height ~/ 2), 255);
  });

  test('launcher foreground is the mark on a transparent canvas', () async {
    final bytes = await File(
      'android/app/src/main/res/drawable-nodpi/soup_launcher_art.png',
    ).readAsBytes();
    final (width, height, alpha) = await decode(bytes);
    expect(width, height);
    for (var i = 0; i < width; i++) {
      expect(alpha(i, 0), 0);
      expect(alpha(0, i), 0);
    }
    expect(alpha(width ~/ 2, height ~/ 2), 0, reason: 'The ring is hollow');
    expect(
      alpha(width ~/ 2, height * 3 ~/ 4),
      255,
      reason: 'The fill line sits in the lower half',
    );
  });

  for (final size in [24.0, 40.0, 64.0]) {
    testWidgets('brand mark has correct bounds and no tint at $size', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: SoupTheme.onboarding,
          home: Center(child: SoupMark(size: size)),
        ),
      );
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, const AssetImage(SoupMark.assetName));
      expect(image.color, isNull);
      expect(image.excludeFromSemantics, isTrue);
      expect(tester.getSize(find.byType(SoupMark)), Size.square(size));
      expect(tester.takeException(), isNull);
    });
  }
}

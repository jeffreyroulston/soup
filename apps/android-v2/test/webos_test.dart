import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soup_v2/src/platform.dart';
import 'package:soup_v2/src/ui/widgets/design_scale.dart';

void main() {
  test('tests never run as webOS', () {
    expect(isWebos, isFalse);
    expect(videoBackdrop, const Color(0xFF000000));
  });

  testWidgets('remote Back keys replay Android system back', (tester) async {
    // The test binding doesn't listen on the engine's channel buffers, so
    // catch what a device's framework would receive.
    final sent = <String>[];
    ui.channelBuffers.setListener(SystemChannels.navigation.name, (data, _) {
      sent.add(SystemChannels.navigation.codec.decodeMethodCall(data).method);
    });
    addTearDown(
      () => ui.channelBuffers.clearListener(SystemChannels.navigation.name),
    );
    installWebosBackKey();
    await tester.pumpWidget(const MaterialApp(home: Text('home')));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    expect(sent, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyEvent(LogicalKeyboardKey.browserBack, platform: 'web');
    expect(sent, ['popRoute', 'popRoute']);
  });

  testWidgets('ScreenSpace gives video the screen size under DesignScale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const video = Key('video');
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: DesignScale(
          child: ScreenSpace(child: SizedBox.expand(key: video)),
        ),
      ),
    );
    // The box the webOS plugin measures is screen-sized…
    expect(tester.getSize(find.byKey(video)), const Size(1920, 1080));
    // …and still paints over the whole screen.
    expect(
      tester.getRect(find.byKey(video)),
      Offset.zero & const Size(1920, 1080),
    );
  });
}

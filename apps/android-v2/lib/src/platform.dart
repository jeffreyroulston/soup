import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'ui/widgets/design_scale.dart';

/// Running on an LG webOS TV (flutter-webOS). Soup only ships for Android and
/// webOS, so a Linux runtime outside `flutter test` is webOS;
/// `--dart-define=SOUP_WEBOS=true|false` forces it either way.
final bool isWebos = switch (const String.fromEnvironment('SOUP_WEBOS')) {
  'true' => true,
  'false' => false,
  _ =>
    !kIsWeb &&
        Platform.isLinux &&
        !Platform.environment.containsKey('FLUTTER_TEST'),
};

/// What sits behind the video. webOS draws video on a hardware plane beneath
/// the Flutter surface (the app is `transparent` in appinfo.json), so anything
/// opaque under the player would hide it.
Color get videoBackdrop =>
    isWebos ? const Color(0x00000000) : const Color(0xFF000000);

/// webOS keeps the remote's Back key for itself and closes the app, unless
/// the window claims it (what `disableBackHistoryAPI` does for web apps).
/// Claimed, it arrives as an Escape key event; replay that as the `popRoute`
/// message Android's system back sends, so every `PopScope` behaves the same
/// on both.
void installWebosBackKey() {
  // The window must exist first, so wait for the first frame.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(
      const MethodChannel('webos/system').invokeMethod<void>('windowProperty', {
        'property': '_WEBOS_ACCESS_POLICY_KEYS_BACK',
        'value': 'true',
      }),
    );
  });
  HardwareKeyboard.instance.addHandler((event) {
    if (event is! KeyDownEvent) return false;
    if (_backKeys.contains(event.logicalKey)) {
      ui.channelBuffers.push(
        SystemChannels.navigation.name,
        SystemChannels.navigation.codec.encodeMethodCall(
          const MethodCall('popRoute'),
        ),
        (_) {},
      );
      return true;
    }
    if (kDebugMode && !_knownKeys.contains(event.logicalKey)) {
      debugPrint(
        'webOS key: ${event.logicalKey.debugName} '
        '(${event.logicalKey.keyId}, physical ${event.physicalKey.usbHidUsage})',
      );
    }
    return false;
  });
}

final _backKeys = {
  LogicalKeyboardKey.goBack,
  LogicalKeyboardKey.browserBack,
  LogicalKeyboardKey.escape,
};

final _knownKeys = {
  LogicalKeyboardKey.arrowUp,
  LogicalKeyboardKey.arrowDown,
  LogicalKeyboardKey.arrowLeft,
  LogicalKeyboardKey.arrowRight,
  LogicalKeyboardKey.enter,
  LogicalKeyboardKey.select,
};

/// Undoes [DesignScale] for [child]: lays it out in screen pixels, then
/// paints it scaled back down so it lands in the same place.
///
/// webOS's video plane is positioned from the video widget's own box size,
/// which ignores ancestor transforms, so under [DesignScale] it would get the
/// 1440×810 design size instead of the screen's and not fill the TV.
class ScreenSpace extends StatelessWidget {
  const ScreenSpace({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final view = View.of(context);
    final screen = view.physicalSize / view.devicePixelRatio;
    final scale = math.min(
      screen.width / DesignScale.designWidth,
      screen.height / DesignScale.designHeight,
    );
    if (!scale.isFinite || scale <= 0 || scale == 1) return child;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest * scale;
        return OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: size.width,
          maxWidth: size.width,
          minHeight: size.height,
          maxHeight: size.height,
          child: Transform.scale(
            scale: 1 / scale,
            alignment: Alignment.topLeft,
            child: child,
          ),
        );
      },
    );
  }
}

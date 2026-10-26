import 'package:flutter/widgets.dart';

import 'platform.dart';
import 'ui/widgets/soup_text_field.dart';

/// Which UI the app runs: the 10-foot D-pad UI on Android TV, or the touch UI
/// on phones and tablets. Everything below the screens (catalog, playback
/// logic, auth) is shared; only presentation switches on this.
enum FormFactor {
  tv,
  touch;

  bool get isTouch => this == touch;

  /// `--dart-define=SOUP_FORM_FACTOR=touch|tv` forces one (e.g. the touch UI
  /// on the TV emulator); otherwise webOS and Android TV (leanback) get [tv].
  static Future<FormFactor> detect() async {
    switch (const String.fromEnvironment('SOUP_FORM_FACTOR')) {
      case 'touch':
        return touch;
      case 'tv':
        return tv;
    }
    if (isWebos) return tv;
    return await TvTextInput.isTelevision() ? tv : touch;
  }

  /// The nearest [FormFactorScope]; [tv] when there is none (tests, and
  /// screens built directly), so existing callers keep the TV layout.
  static FormFactor of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FormFactorScope>()?.value ??
      tv;

  /// Like [of] without a dependency, for `initState`/`dispose`.
  static FormFactor read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<FormFactorScope>()?.value ?? tv;
}

class FormFactorScope extends InheritedWidget {
  const FormFactorScope({required this.value, required super.child, super.key});

  final FormFactor value;

  @override
  bool updateShouldNotify(FormFactorScope old) => value != old.value;
}

extension FormFactorContext on BuildContext {
  bool get isTouch => FormFactor.of(this).isTouch;
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Root frame for phones and tablets: the real screen size and safe areas
/// (unlike TV's fixed [DesignScale] canvas), with text scaling capped so the
/// dense poster layouts still fit.
class TouchFrame extends StatelessWidget {
  const TouchFrame({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light.copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ),
    child: MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: ColoredBox(color: Colors.black, child: child),
    ),
  );
}

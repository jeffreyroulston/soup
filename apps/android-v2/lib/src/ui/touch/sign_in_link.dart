import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'touch_widgets.dart';

/// Touch stand-in for a sign-in QR code: you can't scan your own screen, so
/// open the link in the browser instead.
class SignInLinkButton extends StatelessWidget {
  const SignInLinkButton({
    required this.url,
    required this.label,
    this.expand = true,
    super.key,
  });

  final Uri url;
  final String label;
  final bool expand;

  @override
  Widget build(BuildContext context) => TouchButton(
    label: label,
    icon: Icons.open_in_new_rounded,
    expand: expand,
    height: 52,
    onPressed: () =>
        unawaited(launchUrl(url, mode: LaunchMode.externalApplication)),
  );
}

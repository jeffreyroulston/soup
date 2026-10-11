import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:soup_core/soup_core.dart';

import '../../ui/theme/soup_tokens.dart';
import '../../ui/widgets/glass.dart';
import '../../ui/widgets/soup_button.dart';

/// Web login card (glass-strong, 28px radius) driven by Soup device-link.
class LoginScreen extends StatelessWidget {
  const LoginScreen({required this.viewModel, super.key});

  final SoupDeviceLinkViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 560,
          child: Glass(
            strong: true,
            radius: SoupRadii.spotlight,
            padding: const EdgeInsets.all(44),
            child: ListenableBuilder(
              listenable: viewModel,
              builder: (context, _) => _content(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final phase = viewModel.phase;
    switch (phase) {
      case SoupDeviceLinkPhase.waiting:
        return _qr();
      case SoupDeviceLinkPhase.expired:
        return _message(
          'Code expired',
          'Request a new code to keep signing in.',
          action: 'New code',
          onAction: () => viewModel.startDeviceLink(newCode: true),
        );
      case SoupDeviceLinkPhase.error:
      case SoupDeviceLinkPhase.needsGoogleSignIn:
        return _message(
          phase == SoupDeviceLinkPhase.error
              ? 'Something went wrong'
              : 'Sign in again',
          viewModel.error ??
              viewModel.exchangeError ??
              'Your Soup session ended. Sign in with Google again.',
          action: 'Try again',
          onAction: () => viewModel.startDeviceLink(newCode: true),
        );
      case SoupDeviceLinkPhase.loadingRoster:
        return _busy('Loading your servers…');
      case SoupDeviceLinkPhase.connectingTransport:
        return _busy('Connecting to your server over Tailscale…');
      case SoupDeviceLinkPhase.exchanging:
      case SoupDeviceLinkPhase.ready:
        return _busy('Signing in to Jellyfin…');
      case SoupDeviceLinkPhase.idle:
      case SoupDeviceLinkPhase.starting:
      case SoupDeviceLinkPhase.refreshing:
        return _busy('Getting things ready…');
    }
  }

  Widget _qr() {
    final link = viewModel.link;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('soup', style: SoupType.style(size: 64, weight: 800, letterSpacing: -2.5)),
        const SizedBox(height: 24),
        if (link != null) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: QrImageView(
              data: link.verificationUriComplete.toString(),
              size: 200,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Scan with your phone to sign in',
            style: SoupType.style(size: 18, weight: 600, color: SoupColors.ink2),
          ),
          const SizedBox(height: 8),
          Text(
            '${link.verificationUri.host}${link.verificationUri.path} · ${link.userCode}',
            style: SoupType.style(size: 15, color: SoupColors.muted),
          ),
        ],
      ],
    );
  }

  Widget _busy(String text) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('soup', style: SoupType.style(size: 64, weight: 800, letterSpacing: -2.5)),
      const SizedBox(height: 28),
      const SizedBox(
        width: 32,
        height: 32,
        child: CircularProgressIndicator(
          strokeWidth: 3,
          color: SoupColors.accent,
          backgroundColor: Color(0xFF3A3A3C),
        ),
      ),
      const SizedBox(height: 20),
      Text(text, textAlign: TextAlign.center, style: SoupType.style(size: 18, color: SoupColors.ink2)),
    ],
  );

  Widget _message(
    String title,
    String body, {
    required String action,
    required VoidCallback onAction,
  }) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(title, textAlign: TextAlign.center, style: SoupType.style(size: 38, weight: 800, letterSpacing: -1)),
      const SizedBox(height: 12),
      Text(body, textAlign: TextAlign.center, style: SoupType.style(size: 18, color: SoupColors.muted)),
      const SizedBox(height: 28),
      SoupButton(label: action, onPressed: onAction, autofocus: true),
    ],
  );
}

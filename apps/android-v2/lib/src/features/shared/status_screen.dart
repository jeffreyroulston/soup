import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../ui/theme/soup_tokens.dart';
import '../../ui/widgets/soup_button.dart';

/// Startup / reconnect states: wordmark, message, optional QR + retry.
class StatusScreen extends StatelessWidget {
  const StatusScreen({
    required this.title,
    required this.message,
    this.busy = false,
    this.onRetry,
    this.authorizationUrl,
    this.secondaryLabel,
    this.onSecondary,
    super.key,
  });

  final String title;
  final String message;
  final bool busy;
  final VoidCallback? onRetry;
  final Uri? authorizationUrl;

  /// Optional second action, e.g. "Sign out" when retrying can't help.
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'soup',
                style: SoupType.style(size: 56, weight: 800, letterSpacing: -2),
              ),
              const SizedBox(height: 28),
              Text(
                title,
                textAlign: TextAlign.center,
                style: SoupType.style(size: 34, weight: 800, letterSpacing: -1),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: SoupType.style(size: 20, color: SoupColors.muted),
              ),
              if (authorizationUrl case final url?) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: QrImageView(data: url.toString(), size: 180),
                ),
              ] else if (busy) ...[
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
              ],
              if (onRetry != null) ...[
                const SizedBox(height: 28),
                SoupButton(
                  label: 'Try again',
                  onPressed: onRetry,
                  autofocus: true,
                ),
              ],
              if (onSecondary != null && secondaryLabel != null) ...[
                const SizedBox(height: 14),
                SoupButton(
                  label: secondaryLabel!,
                  onPressed: onSecondary,
                  style: SoupButtonStyle.glass,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

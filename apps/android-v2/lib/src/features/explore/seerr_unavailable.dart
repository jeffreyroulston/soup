import 'package:flutter/material.dart';
import 'package:soup_core/soup_core.dart';

import '../../app_scope.dart';
import '../../data/seerr.dart';
import '../../data/seerr_models.dart';
import '../../form_factor.dart';
import '../../ui/theme/soup_tokens.dart';
import '../../ui/widgets/error_state.dart';
import '../../ui/widgets/soup_button.dart';

/// What Explore shows instead of content when Seerr can't be used: not set
/// up on this server, not answering, or the call itself failed (web
/// `SeerrUnavailable.vue`).
class SeerrUnavailable extends StatelessWidget {
  const SeerrUnavailable({
    required this.status,
    this.error,
    this.onRetry,
    super.key,
  });

  final SeerrStatus? status;
  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    // A Jellyfin failure (signed out, server down) gets the shared treatment.
    if (error case final JellyfinApiException e) {
      return ErrorState(error: e, onRetry: onRetry);
    }
    final touch = context.isTouch;
    final scope = SoupScope.maybeOf(context);
    final server =
        scope?.connection?.serverName ??
        scope?.soupAuth?.selectedServer?.name ??
        'this server';
    final String title;
    final String message;
    var retry = onRetry != null;
    if (status != null && !status!.configured) {
      title = "Explore isn't set up here";
      message =
          'Explore needs a Seerr (Jellyseerr) server. An admin can connect '
          'one under Soup settings in the $server dashboard.';
      retry = false;
    } else if (status != null && !status!.reachable) {
      title = "Can't reach Seerr";
      message =
          "$server couldn't talk to its Seerr server. It may be off or "
          'restarting.';
    } else if (error case final SeerrException e) {
      title = "Explore isn't available";
      message = e.message;
    } else {
      title = "Explore isn't available";
      message = 'Try again in a moment.';
    }
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: touch ? 24 : SoupSpacing.gutter,
        vertical: touch ? 48 : 72,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: SoupType.style(
                  size: touch ? 22 : 30,
                  weight: 800,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: SoupType.style(
                  size: touch ? 15 : 17,
                  color: SoupColors.muted,
                  height: 1.4,
                ),
              ),
              if (status?.error case final detail?) ...[
                const SizedBox(height: 10),
                Text(
                  detail,
                  textAlign: TextAlign.center,
                  style: SoupType.style(size: 12, color: SoupColors.muted),
                ),
              ],
              if (retry) ...[
                const SizedBox(height: 24),
                SoupButton(
                  label: 'Retry',
                  onPressed: onRetry,
                  autofocus: !touch,
                  height: touch ? 48 : 56,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Small note under the search box for viewers without a linked Seerr
/// account: they can browse, not request.
class SeerrNotLinkedNote extends StatelessWidget {
  const SeerrNotLinkedNote({this.size = 13, super.key});
  final double size;

  @override
  Widget build(BuildContext context) => Text(
    'You can browse, but requesting needs a Seerr account linked to your '
    'Jellyfin login. Sign in to Seerr with Jellyfin once and come back.',
    style: SoupType.style(size: size, weight: 600, color: SoupColors.muted),
  );
}

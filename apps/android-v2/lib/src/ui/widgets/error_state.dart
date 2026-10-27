import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../data/connection_status.dart';
import '../../form_factor.dart';
import '../theme/soup_tokens.dart';
import 'soup_button.dart';

/// A load that failed, explained the way a viewer can act on: a friendly
/// title and message for [error] (never the raw exception) and a way out.
///
/// While the server is down it follows the shared [ConnectionStatus]: shows
/// the reconnect countdown and offers "Retry now"; screens reload on their
/// own once it answers again.
class ErrorState extends StatelessWidget {
  const ErrorState({required this.error, this.onRetry, super.key});

  final Object error;

  /// Defaults to refreshing the catalog, which reloads every screen.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scope = SoupScope.maybeOf(context);
    final connection = scope?.connection;
    if (connection == null) return _build(context, scope, null);
    return ListenableBuilder(
      listenable: connection,
      builder: (context, _) => _build(context, scope, connection),
    );
  }

  Widget _build(
    BuildContext context,
    SoupScope? scope,
    ConnectionStatus? connection,
  ) {
    final touch = context.isTouch;
    final reported = ConnectionProblem.of(error);
    // The shared status knows best while the server is down (the failure
    // may have been a timeout that's now a refused connection).
    final problem = reported.retries && connection?.problem != null
        ? connection!.problem!
        : reported;
    final copy = problemCopy(problem, connection?.serverName);
    final waiting = problem.retries && connection?.isDown == true;

    final String label;
    final VoidCallback action;
    if (problem == ConnectionProblem.signedOut && scope != null) {
      label = 'Sign in again';
      action = () => unawaited(scope.onSignOut());
    } else if (waiting) {
      label = 'Retry now';
      action = () => unawaited(connection!.retryNow());
    } else {
      label = 'Try again';
      action = onRetry ?? () => scope?.catalog.refresh();
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
                copy.title,
                textAlign: TextAlign.center,
                style: SoupType.style(
                  size: touch ? 22 : 30,
                  weight: 800,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                copy.message,
                textAlign: TextAlign.center,
                style: SoupType.style(
                  size: touch ? 15 : 17,
                  color: SoupColors.muted,
                  height: 1.4,
                ),
              ),
              if (waiting) ...[
                const SizedBox(height: 12),
                Text(
                  _countdown(connection!),
                  style: SoupType.style(
                    size: 14,
                    weight: 700,
                    color: SoupColors.ink2,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SoupButton(
                label: label,
                onPressed: connection?.isRetrying == true ? null : action,
                autofocus: !touch,
                height: touch ? 48 : 56,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _countdown(ConnectionStatus connection) => connection.isRetrying
    ? 'Reconnecting…'
    : 'Retrying in ${connection.secondsUntilRetry}s';

/// A slim notice while the server is down, so screens that already have data
/// keep showing it instead of an error. Touch can tap it to retry; on TV it's
/// informational (the countdown retries on its own) so it never steals focus.
class ConnectionBanner extends StatelessWidget {
  const ConnectionBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final connection = SoupScope.maybeOf(context)?.connection;
    if (connection == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: connection,
      builder: (context, _) {
        final problem = connection.problem;
        final touch = context.isTouch;
        return IgnorePointer(
          ignoring: problem == null,
          child: AnimatedOpacity(
            opacity: problem == null ? 0 : 1,
            duration: const Duration(milliseconds: 200),
            child: problem == null
                ? const SizedBox.shrink()
                : GestureDetector(
                    onTap: touch
                        ? () => unawaited(connection.retryNow())
                        : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xF2202022),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: SoupColors.faint),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: SoupColors.accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              '${problemCopy(problem, connection.serverName).title}'
                              ' · ${_countdown(connection)}'
                              '${touch && !connection.isRetrying ? ' · Tap to retry' : ''}',
                              overflow: TextOverflow.ellipsis,
                              style: SoupType.style(
                                size: touch ? 13 : 15,
                                weight: 700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        );
      },
    );
  }
}

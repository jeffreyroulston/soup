import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:soup_core/soup_core.dart';

/// Why a request failed, in terms a viewer can act on.
enum ConnectionProblem {
  unreachable,
  timeout,
  signedOut,
  server,
  notFound,
  unknown;

  /// Problems that fix themselves once the server is back, so the app retries
  /// on its own.
  bool get retries => this == unreachable || this == timeout || this == server;

  static ConnectionProblem of(Object error) {
    if (error is JellyfinApiException) {
      final status = error.statusCode;
      if (status == 401) return signedOut;
      if (status == 404) return notFound;
      // A proxy in front of a stopped server answers 502/503 (and 504 when
      // it gives up waiting), so those read as the server being away.
      if (status == 502 || status == 503) return unreachable;
      if (status == 504) return timeout;
      if (status != null && status >= 500) return server;
    }
    if (error is TimeoutException) return timeout;
    if (error is SocketException ||
        error is HandshakeException ||
        error is HttpException) {
      return unreachable;
    }
    // http's ClientException and the generated client's ApiException wrap the
    // socket error in their message.
    final text = error.toString();
    if (RegExp(
      r'SocketException|Connection (refused|reset|closed)|Failed host lookup|'
      r'Network is unreachable|No route to host|HandshakeException',
    ).hasMatch(text)) {
      return unreachable;
    }
    if (RegExp(r'TimeoutException|timed out').hasMatch(text)) return timeout;
    return unknown;
  }
}

/// The title and message for [problem]; [server] is the server's name.
({String title, String message}) problemCopy(
  ConnectionProblem problem,
  String? server,
) {
  final name = server ?? 'your server';
  return switch (problem) {
    ConnectionProblem.unreachable => (
      title: "Can't reach $name",
      message:
          'Make sure $name is turned on and connected to your network, then '
          'try again.',
    ),
    ConnectionProblem.timeout => (
      title: "$name isn't responding",
      message: "It's taking too long to answer. It may be busy or restarting.",
    ),
    ConnectionProblem.signedOut => (
      title: "You've been signed out",
      message: 'Sign in again to keep watching.',
    ),
    ConnectionProblem.server => (
      title: '$name ran into a problem',
      message:
          "Try again in a moment. If it keeps happening, check the server's "
          'logs.',
    ),
    ConnectionProblem.notFound => (
      title: "This title isn't available",
      message: 'It may have been removed from $name.',
    ),
    ConnectionProblem.unknown => (
      title: 'Something went wrong',
      message: 'Try again in a moment.',
    ),
  };
}

/// App-wide view of whether the Jellyfin server is answering.
///
/// Screens [report] failures and successes. A retryable failure marks the
/// server down and probes it with backoff (3s, 6s, 12s, 24s, then every 30s);
/// the first probe that answers calls [onRecovered] so every screen reloads.
class ConnectionStatus extends ChangeNotifier {
  ConnectionStatus({
    required this.probe,
    required this.onRecovered,
    String? serverName,
  }) : _serverName = serverName;

  /// Asks the server for its public info; returns its name, throws when it
  /// can't be reached.
  final Future<String> Function() probe;
  final VoidCallback onRecovered;

  static const _backoff = [3, 6, 12, 24, 30];

  String? _serverName;

  /// The server's name once known (learned from the first probe).
  String? get serverName => _serverName;

  ConnectionProblem? _problem;

  /// Set while the server is down.
  ConnectionProblem? get problem => _problem;
  bool get isDown => _problem != null;

  int _attempt = 0;
  int _secondsLeft = 0;

  /// Seconds until the next automatic retry.
  int get secondsUntilRetry => _secondsLeft;

  bool _probing = false;
  bool get isRetrying => _probing;

  Timer? _tick;
  bool _disposed = false;

  /// Learns the server's name in the background; failures are ignored.
  void start() {
    unawaited(
      probe().then((name) {
        if (_disposed || _serverName == name) return;
        _serverName = name;
        notifyListeners();
      }, onError: (Object _) {}),
    );
  }

  void report(Object error) {
    final problem = ConnectionProblem.of(error);
    if (!problem.retries || _disposed) return;
    if (_problem == null) {
      _problem = problem;
      _attempt = 0;
      _schedule();
      notifyListeners();
    }
  }

  void reportOk() {
    if (_problem != null && !_probing) _recovered();
  }

  /// Probes now instead of waiting for the countdown.
  Future<void> retryNow() async {
    if (_probing || _disposed) return;
    _tick?.cancel();
    _probing = true;
    notifyListeners();
    try {
      final name = await probe();
      if (_disposed) return;
      _serverName = name;
      _probing = false;
      _recovered();
    } on Object catch (error) {
      if (_disposed) return;
      _probing = false;
      final problem = ConnectionProblem.of(error);
      _problem = problem.retries ? problem : ConnectionProblem.unreachable;
      _attempt++;
      _schedule();
      notifyListeners();
    }
  }

  void _schedule() {
    _tick?.cancel();
    _secondsLeft = _backoff[_attempt.clamp(0, _backoff.length - 1)];
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (--_secondsLeft <= 0) {
        unawaited(retryNow());
      } else {
        notifyListeners();
      }
    });
  }

  void _recovered() {
    _tick?.cancel();
    final wasDown = _problem != null;
    _problem = null;
    _attempt = 0;
    notifyListeners();
    if (wasDown) onRecovered();
  }

  @override
  void dispose() {
    _disposed = true;
    _tick?.cancel();
    super.dispose();
  }
}

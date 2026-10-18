import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:soup_core/src/data/jellyfin/jellyfin_api.dart';

/// Serves Jellyfin media to the platform player from a loopback port, adding
/// the session's auth headers on the way through.
///
/// Anything on the device can reach a loopback port, so every local URL
/// carries a random per-bridge path prefix, and only media paths are
/// forwarded. Without both, any app could use the user's token against the
/// whole Jellyfin API.
class PlaybackBridge {
  PlaybackBridge(this._transport, this._session, this._headers)
    : _secret = _randomSecret();

  final http.Client _transport;
  final JellyfinSession _session;
  final Map<String, String> _headers;
  final String _secret;
  HttpServer? _server;

  bool get isRunning => _server != null;

  Future<void> start() async {
    if (_server != null) return;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    unawaited(
      server.forEach(_handle).catchError((Object _) {
        // Individual player requests receive their own HTTP error response.
      }),
    );
  }

  Uri localUriFor(Uri upstream) {
    final server = _server;
    if (server == null) {
      throw StateError('Playback bridge has not started.');
    }
    if (upstream.host != _session.serverUrl.host ||
        _effectivePort(upstream) != _effectivePort(_session.serverUrl)) {
      throw const JellyfinApiException(
        'Jellyfin returned a playback URL for an unexpected server.',
      );
    }
    if (!_isMediaPath(upstream.path)) {
      throw const JellyfinApiException(
        'Jellyfin returned a playback URL outside its media paths.',
      );
    }
    return upstream.replace(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      path: '/$_secret${upstream.path}',
    );
  }

  Future<void> _handle(HttpRequest incoming) async {
    final response = incoming.response;
    if (incoming.method != 'GET' && incoming.method != 'HEAD') {
      response.statusCode = HttpStatus.methodNotAllowed;
      await response.close();
      return;
    }
    final prefix = '/$_secret/';
    final localPath = incoming.uri.path;
    if (!localPath.startsWith(prefix) ||
        !_isMediaPath(localPath.substring(prefix.length - 1))) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    try {
      final upstream = _session.serverUrl.replace(
        path: localPath.substring(prefix.length - 1),
        query: incoming.uri.hasQuery ? incoming.uri.query : null,
      );
      final request = http.Request(incoming.method, upstream);
      incoming.headers.forEach((name, values) {
        if (_forwardedRequestHeaders.contains(name.toLowerCase())) {
          request.headers[name] = values.join(',');
        }
      });
      request.headers.addAll(_headers);
      final upstreamResponse = await _transport.send(request);
      response.statusCode = upstreamResponse.statusCode;
      if (upstreamResponse.reasonPhrase case final reason?) {
        response.reasonPhrase = reason;
      }
      upstreamResponse.headers.forEach((name, value) {
        if (!_responseHopByHop.contains(name.toLowerCase())) {
          response.headers.set(name, value);
        }
      });
      if (incoming.method != 'HEAD') {
        await response.addStream(upstreamResponse.stream);
      }
    } on Object {
      try {
        response.statusCode = HttpStatus.badGateway;
      } on StateError {
        // The upstream response had already started streaming.
      }
    } finally {
      await response.close();
    }
  }

  Future<void> close() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  /// Whether [path] is under the server's `Videos/` or `Audio/` routes.
  bool _isMediaPath(String path) {
    final base = _session.serverUrl.path.endsWith('/')
        ? _session.serverUrl.path
        : '${_session.serverUrl.path}/';
    if (!path.startsWith(base)) return false;
    final rest = path.substring(base.length);
    if (rest.split('/').contains('..')) return false;
    // Jellyfin's own TranscodingUrl uses lowercase `/videos/`.
    final route = rest.toLowerCase();
    return route.startsWith('videos/') || route.startsWith('audio/');
  }

  static String _randomSecret() {
    final random = Random.secure();
    return [
      for (var i = 0; i < 16; i++)
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }

  /// What a player needs for ranged and adaptive streaming. Everything else,
  /// including any auth a caller sends, is dropped.
  static const _forwardedRequestHeaders = {
    'accept',
    'accept-encoding',
    'if-range',
    'range',
    'user-agent',
  };

  static const _responseHopByHop = {
    'connection',
    'keep-alive',
    'proxy-authenticate',
    'proxy-authorization',
    'te',
    'trailer',
    'transfer-encoding',
    'upgrade',
  };

  static int _effectivePort(Uri uri) {
    if (uri.hasPort) return uri.port;
    return uri.scheme == 'https' ? 443 : 80;
  }
}

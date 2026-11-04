import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:soup_core/soup_core.dart';

import '../app_scope.dart';
import 'catalog.dart';
import 'mock_seerr.dart';
import 'seerr_models.dart';

/// A failed Seerr call: the plugin's or Seerr's own `{ error, message }`,
/// with the HTTP status. Deliberately not a [JellyfinApiException], so a down
/// Seerr never reads as a down Jellyfin.
class SeerrException implements Exception {
  const SeerrException(this.status, this.code, this.message);

  final int status;

  /// Machine code: `seerr_not_configured`, `seerr_unreachable`,
  /// `seerr_user_not_linked`, or Seerr's own.
  final String code;
  final String message;

  bool get notLinked => code == 'seerr_user_not_linked';

  @override
  String toString() => message;
}

/// Everything Explore reads or writes. Live impl: [JellyfinSeerr] (through
/// the Soup plugin's `SoupSeerr` endpoints); offline impl: [MockSeerr].
///
/// Port of apps/web/app/composables/useSeerr.ts + useSeerrQueries.ts.
abstract class Seerr extends ChangeNotifier {
  /// Last known status; null until [loadStatus] has answered once. The nav
  /// bar shows the Explore tab when it says Seerr is configured and up.
  final status = ValueNotifier<SeerrStatus?>(null);

  Future<SeerrStatus>? _status;
  int _revision = 0;

  /// Bumped (and listeners notified) after a request is made or withdrawn.
  int get revision => _revision;

  /// Loads the status once per session (or again with [force]); failures
  /// aren't cached so the next screen retries.
  Future<SeerrStatus> loadStatus({bool force = false}) {
    if (!force && _status != null) return _status!;
    late final Future<SeerrStatus> future;
    future = fetchStatus().then(
      (value) {
        status.value = value;
        return value;
      },
      onError: (Object error, StackTrace stack) {
        if (identical(_status, future)) _status = null;
        return Future<SeerrStatus>.error(error, stack);
      },
    );
    _status = future;
    return future;
  }

  @protected
  Future<SeerrStatus> fetchStatus();

  Future<SeerrSearchResults> search(String term, {int page = 1});

  /// A `discover/...` catalogue row (trending, movies, tv, movies/upcoming).
  Future<SeerrSearchResults> discover(String path, {int page = 1});

  /// Null when Seerr/TMDB has no such title.
  Future<SeerrDetails?> details(SeerrMediaType type, int tmdbId);

  Future<SeerrRequestsPage> myRequests(
    SeerrRequestFilter filter, {
    int take = 20,
    int skip = 0,
  });

  Future<void> createRequest(SeerrRequestPayload payload);
  Future<void> cancelRequest(int requestId);

  // ── cache ────────────────────────────────────────────────────────────────
  final _memo = <String, ({DateTime at, Future<Object?> value})>{};

  @protected
  Future<T> cached<T>(
    String key,
    Future<T> Function() load, {
    Duration ttl = const Duration(minutes: 5),
  }) {
    final hit = _memo[key];
    if (hit != null && DateTime.now().difference(hit.at) < ttl) {
      return hit.value as Future<T>;
    }
    final future = load();
    _memo[key] = (at: DateTime.now(), value: future);
    unawaited(
      future.then<void>(
        (_) {},
        onError: (Object _) {
          if (identical(_memo[key]?.value, future)) _memo.remove(key);
        },
      ),
    );
    return future;
  }

  /// Drops everything that carries request state, so title pages and the
  /// Requests tab reload after a request is made or withdrawn.
  @protected
  void invalidate() {
    _memo.clear();
    _revision++;
    notifyListeners();
  }

  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    status.dispose();
    super.dispose();
  }

  /// One per signed-in session, alongside the catalog: live when the scope
  /// has a Jellyfin API, the mock otherwise.
  static final _bySession = Expando<Seerr>('seerr');

  /// Tests: use [seerr] for the session behind [catalog] instead of the
  /// default mock.
  @visibleForTesting
  static void install(Catalog catalog, Seerr seerr) =>
      _bySession[catalog] = seerr;

  static Seerr of(BuildContext context) {
    final scope = SoupScope.of(context);
    final api = scope.api;
    final session = scope.session;
    return _bySession[scope.catalog] ??= api == null || session == null
        ? MockSeerr()
        : JellyfinSeerr(api, session);
  }
}

/// Live Seerr over the Soup plugin: the browser-side of
/// plugins/jellyfin-soup `SoupSeerrController`.
class JellyfinSeerr extends Seerr {
  JellyfinSeerr(this._api, this._session);

  final JellyfinApi _api;
  final JellyfinSession _session;

  static const _timeout = Duration(seconds: 25);

  Future<Object?> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    final uri = _session.serverUrl
        .resolve(path)
        .replace(queryParameters: query);
    final request = http.Request(method, uri)
      ..headers.addAll(_api.authenticatedHeaders(_session));
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final response = await http.Response.fromStream(
      await _api.transport.send(request).timeout(_timeout),
    );
    if (response.statusCode == 401) {
      throw const JellyfinApiException(
        'Your Jellyfin session has expired. Sign in again.',
        statusCode: 401,
      );
    }
    Object? decoded;
    if (response.body.isNotEmpty) {
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        decoded = null;
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded is Map ? decoded : const <Object?, Object?>{};
      final code = error['error'];
      final message = error['message'];
      throw SeerrException(
        response.statusCode,
        code is String && code.isNotEmpty ? code : 'seerr_error',
        message is String && message.isNotEmpty
            ? message
            : 'Seerr returned HTTP ${response.statusCode}.',
      );
    }
    return decoded;
  }

  Future<Object?> _browse(String path, Map<String, String> query) =>
      _send('GET', 'SoupSeerr/Browse/$path', query: query);

  @override
  Future<SeerrStatus> fetchStatus() async =>
      mapSeerrStatus(await _send('GET', 'SoupSeerr/Status'));

  @override
  Future<SeerrSearchResults> search(String term, {int page = 1}) {
    final trimmed = term.trim();
    if (trimmed.isEmpty) return Future.value(const SeerrSearchResults());
    return cached(
      'search:$trimmed:$page',
      () async => mapSeerrResults(
        await _browse('search', {'query': trimmed, 'page': '$page'}),
      ),
      ttl: const Duration(minutes: 2),
    );
  }

  @override
  Future<SeerrSearchResults> discover(String path, {int page = 1}) => cached(
    'discover:$path:$page',
    () async => mapSeerrResults(await _browse(path, {'page': '$page'})),
    ttl: const Duration(minutes: 10),
  );

  @override
  Future<SeerrDetails?> details(SeerrMediaType type, int tmdbId) =>
      cached('details:${type.apiValue}:$tmdbId', () async {
        try {
          return mapSeerrDetails(
            await _browse('${type.apiValue}/$tmdbId', const {}),
            type,
          );
        } on SeerrException catch (e) {
          if (e.status == 404) return null;
          rethrow;
        }
      });

  @override
  Future<SeerrRequestsPage> myRequests(
    SeerrRequestFilter filter, {
    int take = 20,
    int skip = 0,
  }) => cached(
    'requests:${filter.apiValue}:$take:$skip',
    () async => mapSeerrRequestsPage(
      await _send(
        'GET',
        'SoupSeerr/Requests',
        query: {'take': '$take', 'skip': '$skip', 'filter': filter.apiValue},
      ),
    ),
    ttl: const Duration(minutes: 1),
  );

  @override
  Future<void> createRequest(SeerrRequestPayload payload) async {
    await _send('POST', 'SoupSeerr/Request', body: payload.toJson());
    invalidate();
  }

  @override
  Future<void> cancelRequest(int requestId) async {
    await _send('DELETE', 'SoupSeerr/Request/$requestId');
    invalidate();
  }
}

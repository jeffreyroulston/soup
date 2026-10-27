import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:soup_core/src/data/jellyfin/jellyfin_api.dart';
import 'package:soup_core/src/data/playback/playback_bridge.dart';

void main() {
  test(
    'forwards authentication, byte ranges, status, and response bytes',
    () async {
      late String token;
      late String range;
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => upstream.close(force: true));
      upstream.listen((request) async {
        token = request.headers.value('x-emby-token') ?? '';
        range = request.headers.value(HttpHeaders.rangeHeader) ?? '';
        request.response
          ..statusCode = HttpStatus.partialContent
          ..headers.set(HttpHeaders.contentRangeHeader, 'bytes 10-12/100')
          ..add([10, 11, 12]);
        await request.response.close();
      });
      final transport = IOClient(HttpClient());
      addTearDown(transport.close);
      final session = JellyfinSession(
        serverUrl: Uri.parse('http://127.0.0.1:${upstream.port}/jellyfin/'),
        serverId: 'server',
        userId: 'user',
        userName: 'Alex',
        accessToken: 'token',
      );
      final bridge = PlaybackBridge(transport, session, const {
        'X-Emby-Token': 'token',
      });
      await bridge.start();
      addTearDown(bridge.close);
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final local = bridge.localUriFor(
        Uri.parse(
          'http://127.0.0.1:${upstream.port}/jellyfin/Videos/item/stream.mp4?Static=true',
        ),
      );

      final request = await client.getUrl(local);
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=10-12');
      final response = await request.close();
      final bytes = await response.fold<List<int>>(
        [],
        (all, part) => all..addAll(part),
      );

      expect(response.statusCode, HttpStatus.partialContent);
      expect(
        response.headers.value(HttpHeaders.contentRangeHeader),
        'bytes 10-12/100',
      );
      expect(bytes, [10, 11, 12]);
      expect(token, 'token');
      expect(range, 'bytes=10-12');
    },
  );

  test('keeps relative HLS segment paths on the loopback bridge', () async {
    final requestedPaths = <String>[];
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => upstream.close(force: true));
    upstream.listen((request) async {
      requestedPaths.add(request.uri.path);
      if (request.uri.path.endsWith('.m3u8')) {
        request.response.write('#EXTM3U\nsegment0.ts\n');
      } else {
        request.response.add(utf8.encode('segment'));
      }
      await request.response.close();
    });
    final transport = IOClient(HttpClient());
    addTearDown(transport.close);
    final session = JellyfinSession(
      serverUrl: Uri.parse('http://127.0.0.1:${upstream.port}/'),
      serverId: 'server',
      userId: 'user',
      userName: 'Alex',
      accessToken: 'token',
    );
    final bridge = PlaybackBridge(transport, session, const {});
    await bridge.start();
    addTearDown(bridge.close);
    final client = http.Client();
    addTearDown(client.close);
    final manifest = bridge.localUriFor(
      Uri.parse('http://127.0.0.1:${upstream.port}/Videos/item/master.m3u8'),
    );

    final body = await client.read(manifest);
    final segment = manifest.resolve(body.trim().split('\n').last);
    expect(await client.read(segment), 'segment');
    expect(requestedPaths, [
      '/Videos/item/master.m3u8',
      '/Videos/item/segment0.ts',
    ]);
  });

  test('rejects playback URLs for a different origin', () async {
    final session = JellyfinSession(
      serverUrl: Uri.parse('http://jellyfin:8096/'),
      serverId: 'server',
      userId: 'user',
      userName: 'Alex',
      accessToken: 'token',
    );
    final transport = http.Client();
    addTearDown(transport.close);
    final bridge = PlaybackBridge(transport, session, const {});
    await bridge.start();
    addTearDown(bridge.close);

    expect(
      () => bridge.localUriFor(Uri.parse('http://unexpected:8096/video')),
      throwsA(isA<JellyfinApiException>()),
    );
  });

  group('local access', () {
    late HttpServer upstream;
    late List<String> requested;
    late PlaybackBridge bridge;
    late http.Client client;

    setUp(() async {
      requested = [];
      upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      upstream.listen((request) async {
        requested.add(
          '${request.uri.path} auth=${request.headers.value('authorization')}',
        );
        request.response.write('ok');
        await request.response.close();
      });
      final session = JellyfinSession(
        serverUrl: Uri.parse('http://127.0.0.1:${upstream.port}/jellyfin/'),
        serverId: 'server',
        userId: 'user',
        userName: 'Alex',
        accessToken: 'token',
      );
      final transport = IOClient(HttpClient());
      bridge = PlaybackBridge(transport, session, const {
        'X-Emby-Token': 'token',
      });
      await bridge.start();
      client = http.Client();
      addTearDown(() async {
        client.close();
        await bridge.close();
        transport.close();
        await upstream.close(force: true);
      });
    });

    Uri local(String path) => bridge.localUriFor(
      Uri.parse('http://127.0.0.1:${upstream.port}/jellyfin/$path'),
    );

    test('local URLs carry a secret prefix', () {
      final uri = local('Videos/item/stream.mp4');
      expect(uri.pathSegments.first, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(uri.path, endsWith('/jellyfin/Videos/item/stream.mp4'));
    });

    test('requests without the prefix never reach Jellyfin', () async {
      final port = local('Videos/item/stream.mp4').port;
      final response = await client.get(
        Uri.parse('http://127.0.0.1:$port/jellyfin/Users'),
      );
      expect(response.statusCode, HttpStatus.notFound);
      expect(requested, isEmpty);
    });

    test('only media paths are forwarded, even with the prefix', () async {
      final media = local('Videos/item/stream.mp4');
      final users = media.replace(
        path: '/${media.pathSegments.first}/jellyfin/Users',
      );
      final escape = media.replace(
        path: '/${media.pathSegments.first}/jellyfin/Videos/../Users',
      );
      expect((await client.get(users)).statusCode, HttpStatus.notFound);
      expect((await client.get(escape)).statusCode, HttpStatus.notFound);
      expect(requested, isEmpty);
      expect(() => local('System/Logs'), throwsA(isA<JellyfinApiException>()));
    });

    test("Jellyfin's lowercase transcode route is allowed", () async {
      expect(await client.read(local('videos/item/master.m3u8')), 'ok');
    });

    test('caller auth headers are not forwarded', () async {
      await client.get(
        local('Videos/item/stream.mp4'),
        headers: {'Authorization': 'MediaBrowser Token="other"'},
      );
      expect(requested, ['/jellyfin/Videos/item/stream.mp4 auth=null']);
    });
  });
}

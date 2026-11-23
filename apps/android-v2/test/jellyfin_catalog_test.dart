import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:soup_core/soup_core.dart';
import 'package:soup_v2/src/data/jellyfin_catalog.dart';
import 'package:soup_v2/src/data/models.dart';

final _session = JellyfinSession(
  serverUrl: Uri.parse('http://jellyfin/'),
  serverId: 'server',
  userId: 'user',
  userName: 'Alex',
  accessToken: 'token',
);

void main() {
  late List<String> requested;
  late int failuresLeft;

  JellyfinCatalog catalog() {
    final client = MockClient((request) async {
      requested.add(request.url.path);
      if (failuresLeft > 0) {
        failuresLeft--;
        return http.Response('', 500);
      }
      return http.Response('{"Items":[]}', 200);
    });
    addTearDown(client.close);
    final c = JellyfinCatalog(JellyfinApi(client, deviceId: 'd'), _session);
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    requested = [];
    failuresLeft = 0;
  });

  test(
    'a failed load is retried next time, without an unhandled error',
    () async {
      final c = catalog();
      failuresLeft = 1;
      await expectLater(c.libraries(), throwsA(isA<JellyfinApiException>()));
      // An unhandled async error would fail this test from the zone.
      await Future<void>.delayed(Duration.zero);

      await c.libraries(); // the failure wasn't cached
      await c.libraries(); // the success was
      expect(requested.where((p) => p.endsWith('/Views')), hasLength(2));
    },
  );

  test('a watched toggle keeps entries with no per-user state', () async {
    final c = catalog();
    await c.libraries();
    await c.history();
    final before = requested.length;

    c.invalidate();
    await c.libraries();
    await c.history();

    final again = requested.sublist(before);
    expect(again.where((p) => p.endsWith('/Views')), isEmpty);
    expect(again, isNotEmpty); // history refetched
  });

  test('a failed image is fetched again; a loaded one is cached', () async {
    final c = catalog();
    const poster = ImageRef('item', 'Primary', 'tag');
    failuresLeft = 1;
    expect(await c.image(poster), isNull);
    expect(await c.image(poster), isNotNull);
    expect(await c.image(poster), isNotNull);
    expect(requested.where((p) => p.contains('/Images/')), hasLength(2));
  });

  test(
    'userAvatar caches hits and 404s, retries errors, and refetches on refresh',
    () async {
      var status = 500;
      final avatarRequests = <String>[];
      final client = MockClient((request) async {
        avatarRequests.add(request.url.path);
        if (status == 200) return http.Response.bytes([1, 2, 3], 200);
        return http.Response('', status);
      });
      addTearDown(client.close);
      final c = JellyfinCatalog(JellyfinApi(client, deviceId: 'd'), _session);
      addTearDown(c.dispose);

      // Transient 500 returns null and is not cached.
      expect(await c.userAvatar(), isNull);
      expect(avatarRequests, ['/Users/user/Images/Primary']);

      // 404 returns null and is cached across calls and invalidate().
      status = 404;
      expect(await c.userAvatar(), isNull);
      expect(await c.userAvatar(), isNull);
      c.invalidate();
      expect(await c.userAvatar(), isNull);
      expect(avatarRequests, hasLength(2));

      // Explicit refresh() drops the cached avatar and fetches the new picture.
      status = 200;
      c.refresh();
      expect(await c.userAvatar(), [1, 2, 3]);
      expect(await c.userAvatar(), [1, 2, 3]);
      expect(avatarRequests, hasLength(3));
    },
  );
}

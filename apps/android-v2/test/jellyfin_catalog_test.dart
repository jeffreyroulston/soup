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
}

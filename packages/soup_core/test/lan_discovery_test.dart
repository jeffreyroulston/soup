import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soup_core/src/data/jellyfin/lan_discovery.dart';
import 'package:soup_core/src/platform/android_network_interfaces.dart';

/// An address no local interface owns (it won't bind), then loopback.
class _Interfaces extends AndroidNetworkInterfaces {
  const _Interfaces(this.entries);

  final List<({InternetAddress address, InternetAddress broadcast})> entries;

  @override
  Future<List<({InternetAddress address, InternetAddress broadcast})>>
  broadcasts() async => entries;
}

final _unbindable = (
  address: InternetAddress('203.0.113.7'),
  broadcast: InternetAddress('203.0.113.255'),
);
final _loopback = (
  address: InternetAddress.loopbackIPv4,
  broadcast: InternetAddress.loopbackIPv4,
);

void main() {
  test('an interface that fails to bind is skipped, not fatal', () async {
    final session = SocketLanDiscoverySession(
      interfaces: _Interfaces([_unbindable, _loopback]),
    );
    addTearDown(session.close);

    // Before, the first bind failure failed the whole session.
    await session.ready;
    session.broadcast([1, 2, 3]);
  });

  test('when no interface binds, the session fails', () async {
    final session = SocketLanDiscoverySession(
      interfaces: _Interfaces([_unbindable]),
    );
    addTearDown(session.close);

    await expectLater(session.ready, throwsA(isA<SocketException>()));
  });
}

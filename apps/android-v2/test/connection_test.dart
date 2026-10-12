import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:soup_core/soup_core.dart';
import 'package:soup_v2/src/app_scope.dart';
import 'package:soup_v2/src/data/connection_status.dart';
import 'package:soup_v2/src/data/mock_catalog.dart';
import 'package:soup_v2/src/data/playback_prefs.dart';
import 'package:soup_v2/src/ui/theme/soup_theme.dart';
import 'package:soup_v2/src/ui/widgets/error_state.dart';

void main() {
  test('failures are classified into problems a viewer can act on', () {
    expect(
      ConnectionProblem.of(const SocketException('Connection refused')),
      ConnectionProblem.unreachable,
    );
    expect(
      ConnectionProblem.of(
        http.ClientException(
          'SocketException: Connection refused (OS Error: errno = 111)',
        ),
      ),
      ConnectionProblem.unreachable,
    );
    expect(
      ConnectionProblem.of(TimeoutException('slow')),
      ConnectionProblem.timeout,
    );
    expect(
      ConnectionProblem.of(const JellyfinApiException('x', statusCode: 401)),
      ConnectionProblem.signedOut,
    );
    expect(
      ConnectionProblem.of(const JellyfinApiException('x', statusCode: 500)),
      ConnectionProblem.server,
    );
    expect(
      ConnectionProblem.of(const JellyfinApiException('x', statusCode: 503)),
      ConnectionProblem.unreachable,
    );
    expect(
      ConnectionProblem.of(const JellyfinApiException('x', statusCode: 404)),
      ConnectionProblem.notFound,
    );
    expect(ConnectionProblem.of(StateError('?')), ConnectionProblem.unknown);
  });

  testWidgets('a down server is probed with backoff and recovery reloads', (
    tester,
  ) async {
    var up = false;
    var recovered = 0;
    final status = ConnectionStatus(
      serverName: 'Jeline',
      probe: () async {
        if (!up) throw const SocketException('Connection refused');
        return 'Jeline';
      },
      onRecovered: () => recovered++,
    );

    status.report(const SocketException('Connection refused'));
    expect(status.problem, ConnectionProblem.unreachable);
    expect(status.secondsUntilRetry, 3);

    // First probe after 3s fails, so the next wait doubles.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(status.isDown, isTrue);
    expect(status.secondsUntilRetry, 6);

    up = true;
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
    expect(status.isDown, isFalse);
    expect(recovered, 1);
    status.dispose();
  });

  testWidgets('the error state shows friendly copy, never the raw error', (
    tester,
  ) async {
    final status = ConnectionStatus(
      serverName: 'Jeline',
      probe: () async => throw const SocketException('Connection refused'),
      onRecovered: () {},
    );
    const raw = 'ClientException with SocketException: Connection refused';
    final error = http.ClientException(raw);
    status.report(error);

    final catalog = MockCatalog();
    addTearDown(catalog.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: SoupTheme.dark,
        home: SoupScope(
          catalog: catalog,
          prefs: PlaybackPrefs(),
          onSignOut: () async {},
          connection: status,
          child: Scaffold(body: ErrorState(error: error)),
        ),
      ),
    );

    expect(find.text("Can't reach Jeline"), findsOneWidget);
    expect(find.text('Retrying in 3s'), findsOneWidget);
    expect(find.text('Retry now'), findsOneWidget);
    expect(find.textContaining('SocketException'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    status.dispose();
  });
}

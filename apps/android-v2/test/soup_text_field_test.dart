import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soup_v2/src/ui/theme/soup_theme.dart';
import 'package:soup_v2/src/ui/widgets/soup_text_field.dart';

const _channel = MethodChannel('dev.michaelishri.soup/tv_text_input');

Widget _host(Widget child) => MaterialApp(
  theme: SoupTheme.dark,
  home: Scaffold(
    body: Center(child: SizedBox(width: 480, child: child)),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(TvTextInput.resetForTesting);
  tearDown(() => messenger.setMockMethodCallHandler(_channel, null));

  testWidgets('falls back to a normal text field without the TV channel', (
    tester,
  ) async {
    final controller = TextEditingController();
    var submitted = 0;
    final changes = <String>[];
    await tester.pumpWidget(
      _host(
        SoupTextField(
          controller: controller,
          label: 'Username',
          onChanged: changes.add,
          onSubmitted: () => submitted++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'michael');
    expect(controller.text, 'michael');
    expect(changes, ['michael']);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(submitted, 1);
  });

  testWidgets('on TV, select opens the native editor and applies its result', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'isTelevision' => true,
        'edit' => {'text': 'https://jelly', 'submitted': true},
        _ => null,
      };
    });
    final controller = TextEditingController(text: 'old');
    var submitted = 0;
    await tester.pumpWidget(
      _host(
        SoupTextField(
          controller: controller,
          label: 'Server address',
          url: true,
          action: TextInputAction.next,
          autofocus: true,
          onSubmitted: () => submitted++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Server address'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    final edit = calls.firstWhere((c) => c.method == 'edit');
    expect(edit.arguments, {
      'label': 'Server address',
      'text': 'old',
      'obscureText': false,
      'isUrl': true,
      'next': true,
    });
    expect(controller.text, 'https://jelly');
    expect(submitted, 1);
  });

  testWidgets('on TV, a cancelled edit keeps the text but does not submit', (
    tester,
  ) async {
    messenger.setMockMethodCallHandler(_channel, (call) async {
      return switch (call.method) {
        'isTelevision' => true,
        'edit' => {'text': 'draft', 'submitted': false},
        _ => null,
      };
    });
    final controller = TextEditingController();
    var submitted = 0;
    await tester.pumpWidget(
      _host(
        SoupTextField(
          controller: controller,
          label: 'Password',
          obscure: true,
          autofocus: true,
          onSubmitted: () => submitted++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(controller.text, 'draft');
    expect(submitted, 0);
    // Obscured on screen.
    expect(find.text('•••••'), findsOneWidget);
  });
}

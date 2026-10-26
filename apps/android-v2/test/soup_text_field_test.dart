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

  group('editing in place (webOS)', () {
    setUp(() => SoupTextField.editInPlace = true);
    tearDown(() => SoupTextField.editInPlace = false);

    Future<TextEditingController> pumpField(WidgetTester tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        _host(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(onPressed: () {}, child: const Text('above')),
              SoupTextField(
                controller: controller,
                label: 'Search',
                autofocus: true,
              ),
              TextButton(onPressed: () {}, child: const Text('below')),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      return controller;
    }

    String? focused() => FocusManager.instance.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<TextButton>()
        ?.child
        .toString();

    testWidgets('select opens a live field; Up and Down leave it', (
      tester,
    ) async {
      final controller = await pumpField(tester);
      // Focused, but no keyboard until selected.
      expect(find.byType(TextField), findsNothing);
      expect(tester.testTextInput.isVisible, isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.testTextInput.isVisible, isTrue);
      tester.testTextInput.enterText('dune');
      expect(controller.text, 'dune');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(focused(), contains('below'));
      expect(find.byType(TextField), findsNothing);
      expect(find.text('dune'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(focused(), contains('above'));
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('Back moving focus away ends editing for good', (tester) async {
      await pumpField(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      // The window losing focus to the keyboard parks focus on the root;
      // that alone doesn't end editing.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);

      // What PageScaffold's Back does: focus the nav.
      final below = find.text('below');
      Focus.of(tester.element(below)).requestFocus();
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(focused(), contains('below'));
      expect(find.byType(TextField), findsNothing);
      expect(tester.testTextInput.isVisible, isFalse);
    });

    testWidgets('Done returns to the field without the keyboard', (
      tester,
    ) async {
      await pumpField(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(FocusManager.instance.primaryFocus, isNot(isA<FocusScopeNode>()));
      // Still on the field: select edits again.
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
    });
  });
}

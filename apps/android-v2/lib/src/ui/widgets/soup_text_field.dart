import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../platform.dart';
import '../theme/soup_tokens.dart';
import 'focusable.dart';

class TvTextEdit {
  const TvTextEdit({required this.text, required this.submitted});
  final String text;
  final bool submitted;
}

/// Android TV's IME must edit a native field to own remote navigation, so on
/// TV [SoupTextField] hands editing to a native dialog over this channel.
class TvTextInput {
  const TvTextInput();
  static const _channel = MethodChannel('dev.michaelishri.soup/tv_text_input');

  static Future<bool>? _television;

  /// Cached for the process; false when the channel isn't registered.
  static Future<bool> isTelevision() => _television ??= _probe();

  static Future<bool> _probe() async {
    try {
      return await _channel.invokeMethod<bool>('isTelevision') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Test hook: forget the cached television probe.
  static void resetForTesting() => _television = null;

  Future<TvTextEdit?> edit({
    required String label,
    required String text,
    required bool obscureText,
    required bool isUrl,
    required bool next,
  }) async {
    final result = await _channel.invokeMapMethod<String, dynamic>('edit', {
      'label': label,
      'text': text,
      'obscureText': obscureText,
      'isUrl': isUrl,
      'next': next,
    });
    if (result == null) return null;
    return TvTextEdit(
      text: result['text'] as String,
      submitted: result['submitted'] as bool,
    );
  }

  Future<void> dismiss() async {
    try {
      await _channel.invokeMethod<void>('dismiss');
    } on MissingPluginException {
      // Not running on the Soup activity.
    }
  }
}

/// Web-style input (white/10 fill, 12 radius, ink focus ring).
///
/// On Android TV, selecting the field opens the native editor dialog. On
/// webOS, selecting it swaps in a live text field (and the system keyboard)
/// until focus moves away. On phones, tests and anything else it is a normal
/// text field. [onSubmitted] fires when the user confirms (Done/Next or the
/// IME action).
class SoupTextField extends StatefulWidget {
  const SoupTextField({
    required this.controller,
    required this.label,
    this.hint,
    this.obscure = false,
    this.url = false,
    this.action,
    this.onSubmitted,
    this.onChanged,
    this.focusNode,
    this.autofocus = false,
    this.enabled = true,
    this.tvTextInput = const TvTextInput(),
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscure;
  final bool url;

  /// [TextInputAction.next] makes the TV editor show "Next" instead of "Done".
  final TextInputAction? action;
  final VoidCallback? onSubmitted;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool enabled;
  final TvTextInput tvTextInput;

  /// Edit in place only while selected, as on webOS. A live field that keeps
  /// focus there gets it back (keyboard and all) when the window regains
  /// focus after the keyboard closes, so Back could never leave it.
  @visibleForTesting
  static bool editInPlace = isWebos;

  @override
  State<SoupTextField> createState() => _SoupTextFieldState();
}

class _SoupTextFieldState extends State<SoupTextField> {
  bool? _tv;
  bool _editing = false;
  FocusNode? _ownFocus;
  bool _focused = false;

  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  /// The live field's node while editing in place.
  FocusNode? _inPlace;

  @override
  void initState() {
    super.initState();
    unawaited(
      TvTextInput.isTelevision().then((tv) {
        if (mounted) setState(() => _tv = tv);
      }),
    );
  }

  @override
  void dispose() {
    if (_editing) unawaited(widget.tvTextInput.dismiss());
    _inPlace?.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  Future<void> _edit() async {
    if (_editing || !widget.enabled) return;
    _editing = true;
    TvTextEdit? result;
    try {
      result = await widget.tvTextInput.edit(
        label: widget.label,
        text: widget.controller.text,
        obscureText: widget.obscure,
        isUrl: widget.url,
        next: widget.action == TextInputAction.next,
      );
    } on PlatformException {
      // Leave the field as-is; selecting it again retries.
    } finally {
      _editing = false;
    }
    if (!mounted) return;
    _focus.requestFocus();
    if (result == null) return;
    widget.controller.value = TextEditingValue(
      text: result.text,
      selection: TextSelection.collapsed(offset: result.text.length),
    );
    widget.onChanged?.call(result.text);
    if (result.submitted) widget.onSubmitted?.call();
  }

  void _editInPlace() {
    if (_inPlace != null || !widget.enabled) return;
    final node = FocusNode(debugLabel: 'in-place edit')
      ..addListener(_inPlaceFocusChanged);
    setState(() => _inPlace = node);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_inPlace == node) node.requestFocus();
    });
  }

  void _inPlaceFocusChanged() {
    final node = _inPlace;
    if (node == null || node.hasFocus) return;
    final now = FocusManager.instance.primaryFocus;
    // Focus parked on the root while the app is inactive; it comes back.
    if (now == null || now == FocusManager.instance.rootScope) return;
    setState(() => _inPlace = null);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      node.dispose();
      // Unfocused onto the page scope (Done, or the keyboard closing):
      // land on the field rather than nowhere.
      if (mounted && FocusManager.instance.primaryFocus is FocusScopeNode) {
        _focus.requestFocus();
      }
    });
  }

  /// Up/Down leave the field like any other D-pad move.
  KeyEventResult _inPlaceKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final direction = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowUp => TraversalDirection.up,
      LogicalKeyboardKey.arrowDown => TraversalDirection.down,
      _ => null,
    };
    if (direction == null) return KeyEventResult.ignored;
    _inPlace?.focusInDirection(direction);
    return KeyEventResult.handled;
  }

  static const _fill = Color(0x1AFFFFFF);

  @override
  Widget build(BuildContext context) {
    // Android TV swaps in this field once the probe answers, after a frame
    // of the touch field; a node of its own keeps autofocus working across
    // that swap.
    if (_tv == true) {
      return _tvField(focusNode: widget.focusNode, onActivate: _edit);
    }
    if (SoupTextField.editInPlace) {
      final node = _inPlace;
      if (node == null) {
        return _tvField(focusNode: _focus, onActivate: _editInPlace);
      }
      return Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _inPlaceKey,
        child: _touchField(focusNode: node, autofocus: false),
      );
    }
    return _touchField(focusNode: _focus, autofocus: widget.autofocus);
  }

  Widget _tvField({
    required FocusNode? focusNode,
    required VoidCallback onActivate,
  }) => Focusable(
    focusNode: focusNode,
    autofocus: widget.autofocus,
    onActivate: widget.enabled ? onActivate : null,
    radius: SoupRadii.button,
    scale: 1.0,
    builder: (context, focused) => ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final raw = widget.controller.text;
        final text = widget.obscure ? '•' * raw.length : raw;
        return Semantics(
          label: widget.label,
          value: text,
          button: true,
          enabled: widget.enabled,
          child: ExcludeSemantics(
            child: Container(
              constraints: const BoxConstraints(minHeight: 60),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: focused ? const Color(0x2EFFFFFF) : _fill,
                borderRadius: BorderRadius.circular(SoupRadii.button),
              ),
              alignment: Alignment.centerLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.label,
                    style: SoupType.style(
                      size: 12,
                      weight: 700,
                      color: SoupColors.muted,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    text.isEmpty ? (widget.hint ?? '') : text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SoupType.style(
                      size: 18,
                      weight: 600,
                      color: text.isEmpty
                          ? SoupColors.muted.withValues(alpha: .6)
                          : SoupColors.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );

  Widget _touchField({required FocusNode focusNode, required bool autofocus}) =>
      Container(
        constraints: const BoxConstraints(minHeight: 60),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: _fill,
          borderRadius: BorderRadius.circular(SoupRadii.button),
          border: Border.all(
            color: _focused ? SoupColors.ink : Colors.transparent,
            width: 3,
          ),
        ),
        alignment: Alignment.center,
        child: Focus(
          onFocusChange: (v) => setState(() => _focused = v),
          skipTraversal: true,
          child: TextField(
            controller: widget.controller,
            focusNode: focusNode,
            autofocus: autofocus,
            enabled: widget.enabled,
            obscureText: widget.obscure,
            enableSuggestions: !widget.obscure,
            autocorrect: false,
            keyboardType: widget.url ? TextInputType.url : TextInputType.text,
            textInputAction: widget.action ?? TextInputAction.done,
            onChanged: widget.onChanged,
            onSubmitted: (_) => widget.onSubmitted?.call(),
            cursorColor: SoupColors.accent,
            style: SoupType.style(size: 18, weight: 600),
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: widget.hint,
              border: InputBorder.none,
              labelStyle: SoupType.style(
                size: 16,
                weight: 600,
                color: SoupColors.muted,
              ),
              floatingLabelStyle: SoupType.style(
                size: 14,
                weight: 700,
                color: SoupColors.muted,
              ),
              hintStyle: SoupType.style(
                size: 18,
                weight: 600,
                color: SoupColors.muted.withValues(alpha: .6),
              ),
            ),
          ),
        ),
      );
}

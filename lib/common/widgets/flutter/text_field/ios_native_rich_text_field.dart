import 'package:PiliPlus/common/widgets/flutter/text_field/controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// iOS-only rich text editor backed by a real native UITextView.
///
/// The native side keeps every image emote as one U+FFFC character with a real
/// NSTextAttachment. Dart remains the source of truth for RichTextItem/rawText,
/// so publishing still uses the existing Bilibili token model.
class IOSNativeRichTextField extends StatefulWidget {
  const IOSNativeRichTextField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.readOnly,
    this.onChanged,
    this.onTapWhenReadOnly,
    this.hintText,
    this.style,
    this.minLines = 1,
    this.maxLines = 6,
  });

  final RichTextEditingController controller;
  final FocusNode focusNode;
  final bool readOnly;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTapWhenReadOnly;
  final String? hintText;
  final TextStyle? style;
  final int minLines;
  final int maxLines;

  @override
  State<IOSNativeRichTextField> createState() => _IOSNativeRichTextFieldState();
}

class _IOSNativeRichTextFieldState extends State<IOSNativeRichTextField> {
  MethodChannel? _channel;
  bool _applyingNativeState = false;
  double _height = 96;

  double get _fontSize => widget.style?.fontSize ?? 16;
  double get _lineHeight => _fontSize * 1.35;
  double get _minHeight => widget.minLines * _lineHeight + 12;
  double get _maxHeight => widget.maxLines * _lineHeight + 12;

  @override
  void initState() {
    super.initState();
    _height = _minHeight;
    widget.controller.addListener(_controllerChanged);
    widget.focusNode.addListener(_focusChanged);
  }

  @override
  void didUpdateWidget(covariant IOSNativeRichTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_controllerChanged);
      widget.controller.addListener(_controllerChanged);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_focusChanged);
      widget.focusNode.addListener(_focusChanged);
    }
    if (oldWidget.readOnly != widget.readOnly ||
        oldWidget.hintText != widget.hintText ||
        oldWidget.style != widget.style) {
      _sendState();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_controllerChanged);
    widget.focusNode.removeListener(_focusChanged);
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  void _controllerChanged() {
    if (_applyingNativeState) return;
    _sendState();
  }

  void _focusChanged() {
    _channel?.invokeMethod<void>('setFocus', widget.focusNode.hasFocus);
  }

  String? _emoteLabel(RichTextItem item) {
    var label = item.rawText.trim();
    if (label.isEmpty) return null;

    if (label.length >= 2 && label.startsWith('[') && label.endsWith(']')) {
      var inner = label.substring(1, label.length - 1).trim();
      if (inner.endsWith('表情')) {
        inner = inner.substring(0, inner.length - 2).trim();
      }
      return inner.isEmpty ? null : '[$inner]';
    }

    if (label.endsWith('表情')) {
      label = label.substring(0, label.length - 2).trim();
    }
    return label.isEmpty ? null : label;
  }

  List<Map<String, Object>> _emotes() {
    final result = <Map<String, Object>>[];
    for (final item in widget.controller.items) {
      if (item.type != RichTextType.emoji ||
          item.emote == null ||
          item.range.end != item.range.start + 1) {
        continue;
      }
      final label = _emoteLabel(item);
      if (label == null) continue;
      result.add(<String, Object>{
        'start': item.range.start,
        'label': label,
        'url': item.emote!.url,
      });
    }
    return result;
  }

  Map<String, Object?> _statePayload() {
    final value = widget.controller.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    return <String, Object?>{
      'text': value.text,
      'selectionBase': selection.baseOffset,
      'selectionExtent': selection.extentOffset,
      'readOnly': widget.readOnly,
      'hintText': widget.hintText ?? '',
      'fontSize': _fontSize,
      'emotes': _emotes(),
    };
  }

  void _sendState() {
    _channel?.invokeMethod<void>('setState', _statePayload());
  }

  Future<void> _onPlatformViewCreated(int id) async {
    final channel = MethodChannel('accessibilibili/rich_text_editor/$id');
    _channel = channel;
    channel.setMethodCallHandler(_handleNativeCall);
    await channel.invokeMethod<void>('setState', _statePayload());
    if (widget.focusNode.hasFocus && !widget.readOnly) {
      await channel.invokeMethod<void>('setFocus', true);
    }
  }

  Future<Object?> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'stateChanged':
        final args = Map<Object?, Object?>.from(call.arguments as Map);
        _applyNativeState(args, textMayHaveChanged: true);
        return null;
      case 'selectionChanged':
        final args = Map<Object?, Object?>.from(call.arguments as Map);
        _applyNativeState(args, textMayHaveChanged: false);
        return null;
      case 'focusChanged':
        final focused = call.arguments == true;
        if (focused) {
          if (!widget.focusNode.hasFocus) widget.focusNode.requestFocus();
        } else if (widget.focusNode.hasFocus) {
          widget.focusNode.unfocus();
        }
        return null;
      case 'heightChanged':
        final height = (call.arguments as num?)?.toDouble();
        if (height != null && mounted) {
          final next = height.clamp(_minHeight, _maxHeight).toDouble();
          if ((next - _height).abs() > 0.5) {
            setState(() => _height = next);
          }
        }
        return null;
      case 'tap':
        if (widget.readOnly) widget.onTapWhenReadOnly?.call();
        return null;
    }
    return null;
  }

  TextSelection _selectionFrom(Map<Object?, Object?> args, int textLength) {
    int read(String key, int fallback) {
      final value = args[key];
      return value is num
          ? value.toInt().clamp(0, textLength).toInt()
          : fallback;
    }

    final current = widget.controller.selection;
    final fallback = current.isValid ? current.extentOffset : textLength;
    return TextSelection(
      baseOffset: read('selectionBase', fallback),
      extentOffset: read('selectionExtent', fallback),
    );
  }

  TextRange _composingFrom(Map<Object?, Object?> args, int textLength) {
    final startValue = args['composingStart'];
    final endValue = args['composingEnd'];
    if (startValue is! num || endValue is! num) return TextRange.empty;
    final start = startValue.toInt();
    final end = endValue.toInt();
    if (start < 0 || end < start || end > textLength) return TextRange.empty;
    return TextRange(start: start, end: end);
  }

  void _applyNativeState(
    Map<Object?, Object?> args, {
    required bool textMayHaveChanged,
  }) {
    final oldValue = widget.controller.value;
    final nativeText = textMayHaveChanged && args['text'] is String
        ? args['text']! as String
        : oldValue.text;
    final selection = _selectionFrom(args, nativeText.length);
    final composing = _composingFrom(args, nativeText.length);

    TextEditingDelta delta;
    if (nativeText == oldValue.text) {
      delta = TextEditingDeltaNonTextUpdate(
        oldText: oldValue.text,
        selection: selection,
        composing: composing,
      );
    } else {
      final oldText = oldValue.text;
      var prefix = 0;
      final commonStartLimit = oldText.length < nativeText.length
          ? oldText.length
          : nativeText.length;
      while (prefix < commonStartLimit &&
          oldText.codeUnitAt(prefix) == nativeText.codeUnitAt(prefix)) {
        prefix++;
      }

      var suffix = 0;
      final oldRemaining = oldText.length - prefix;
      final newRemaining = nativeText.length - prefix;
      final commonEndLimit = oldRemaining < newRemaining
          ? oldRemaining
          : newRemaining;
      while (suffix < commonEndLimit &&
          oldText.codeUnitAt(oldText.length - 1 - suffix) ==
              nativeText.codeUnitAt(nativeText.length - 1 - suffix)) {
        suffix++;
      }

      final replacedRange = TextRange(
        start: prefix,
        end: oldText.length - suffix,
      );
      final insertedText = nativeText.substring(
        prefix,
        nativeText.length - suffix,
      );

      if (replacedRange.isCollapsed && insertedText.isNotEmpty) {
        delta = TextEditingDeltaInsertion(
          oldText: oldText,
          textInserted: insertedText,
          insertionOffset: prefix,
          selection: selection,
          composing: composing,
        );
      } else if (!replacedRange.isCollapsed && insertedText.isEmpty) {
        delta = TextEditingDeltaDeletion(
          oldText: oldText,
          deletedRange: replacedRange,
          selection: selection,
          composing: composing,
        );
      } else {
        delta = TextEditingDeltaReplacement(
          oldText: oldText,
          replacementText: insertedText,
          replacedRange: replacedRange,
          selection: selection,
          composing: composing,
        );
      }
    }

    final newValue = delta.apply(oldValue);
    _applyingNativeState = true;
    try {
      widget.controller
        ..syncRichText(delta)
        ..value = newValue;
    } finally {
      _applyingNativeState = false;
    }

    if (textMayHaveChanged && nativeText != oldValue.text) {
      widget.onChanged?.call(nativeText);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      child: SizedBox(
        height: _height,
        child: UiKitView(
          viewType: 'accessibilibili/rich_text_editor',
          layoutDirection: Directionality.of(context),
          creationParams: _statePayload(),
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: _onPlatformViewCreated,
        ),
      ),
    );
  }
}

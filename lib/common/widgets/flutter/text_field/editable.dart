import 'dart:ui' show Locale;
import 'dart:ui' as ui show BoxHeightStyle, BoxWidthStyle;

import 'package:PiliPlus/common/widgets/flutter/text_field/controller.dart';
import 'package:PiliPlus/common/widgets/flutter/text_field/editable_base.dart'
    as base;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' hide RenderEditable;
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

export 'package:PiliPlus/common/widgets/flutter/text_field/editable_base.dart'
    hide RenderEditable;

/// The original editable renderer remains in [base.RenderEditable].
///
/// Inline image emotes are painted as WidgetSpans, whose render-tree plain
/// text contains U+FFFC (Object Replacement Character). iOS VoiceOver exposes
/// that character as an "attachment" while editing. The editing controller,
/// however, keeps a normal one-code-unit placeholder for image emotes.
///
/// Keep accessibility text on exactly the same one-code-unit-per-position
/// model as the real editing value. The native iOS accessibility bridge gets a
/// side table of spoken emote labels, but the text and selection offsets here
/// are never expanded or translated.
class RenderEditable extends base.RenderEditable {
  RenderEditable({
    InlineSpan? text,
    required TextDirection textDirection,
    TextAlign textAlign = TextAlign.start,
    Color? cursorColor,
    Color? backgroundCursorColor,
    ValueNotifier<bool>? showCursor,
    bool? hasFocus,
    required LayerLink startHandleLayerLink,
    required LayerLink endHandleLayerLink,
    int? maxLines = 1,
    int? minLines,
    bool expands = false,
    StrutStyle? strutStyle,
    Color? selectionColor,
    double textScaleFactor = 1.0,
    TextScaler textScaler = TextScaler.noScaling,
    TextSelection? selection,
    required ViewportOffset offset,
    bool ignorePointer = false,
    bool readOnly = false,
    bool forceLine = true,
    TextHeightBehavior? textHeightBehavior,
    TextWidthBasis textWidthBasis = TextWidthBasis.parent,
    String obscuringCharacter = '•',
    bool obscureText = false,
    Locale? locale,
    double cursorWidth = 1.0,
    double? cursorHeight,
    Radius? cursorRadius,
    bool paintCursorAboveText = false,
    Offset cursorOffset = Offset.zero,
    double devicePixelRatio = 1.0,
    ui.BoxHeightStyle selectionHeightStyle = ui.BoxHeightStyle.max,
    ui.BoxWidthStyle selectionWidthStyle = ui.BoxWidthStyle.tight,
    bool? enableInteractiveSelection,
    EdgeInsets floatingCursorAddedMargin = const EdgeInsets.fromLTRB(4, 4, 4, 5),
    TextRange? promptRectRange,
    Color? promptRectColor,
    Clip clipBehavior = Clip.hardEdge,
    required TextSelectionDelegate textSelectionDelegate,
    base.RenderEditablePainter? painter,
    base.RenderEditablePainter? foregroundPainter,
    List<RenderBox>? children,
    required RichTextEditingController controller,
  }) : super(
         text: text,
         textDirection: textDirection,
         textAlign: textAlign,
         cursorColor: cursorColor,
         backgroundCursorColor: backgroundCursorColor,
         showCursor: showCursor,
         hasFocus: hasFocus,
         startHandleLayerLink: startHandleLayerLink,
         endHandleLayerLink: endHandleLayerLink,
         maxLines: maxLines,
         minLines: minLines,
         expands: expands,
         strutStyle: strutStyle,
         selectionColor: selectionColor,
         textScaleFactor: textScaleFactor,
         textScaler: textScaler,
         selection: selection,
         offset: offset,
         ignorePointer: ignorePointer,
         readOnly: readOnly,
         forceLine: forceLine,
         textHeightBehavior: textHeightBehavior,
         textWidthBasis: textWidthBasis,
         obscuringCharacter: obscuringCharacter,
         obscureText: obscureText,
         locale: locale,
         cursorWidth: cursorWidth,
         cursorHeight: cursorHeight,
         cursorRadius: cursorRadius,
         paintCursorAboveText: paintCursorAboveText,
         cursorOffset: cursorOffset,
         devicePixelRatio: devicePixelRatio,
         selectionHeightStyle: selectionHeightStyle,
         selectionWidthStyle: selectionWidthStyle,
         enableInteractiveSelection: enableInteractiveSelection,
         floatingCursorAddedMargin: floatingCursorAddedMargin,
         promptRectRange: promptRectRange,
         promptRectColor: promptRectColor,
         clipBehavior: clipBehavior,
         textSelectionDelegate: textSelectionDelegate,
         painter: painter,
         foregroundPainter: foregroundPainter,
         children: children,
         controller: controller,
       );

  static const MethodChannel _accessibilityChannel = MethodChannel(
    'accessibilibili/accessibility',
  );

  String? _lastNativeEmoteSync;

  bool get _usesA11yEmoteText =>
      defaultTargetPlatform == TargetPlatform.iOS &&
      !obscureText &&
      controller.items.any(
        (item) => item.type == RichTextType.emoji && item.emote != null,
      );

  String? _spokenEmoteName(RichTextItem item) {
    var name = item.rawText.trim();
    if (name.isEmpty) return null;

    // Bilibili image emotes are commonly stored as tokens such as "[doge]".
    // Match the picker wording: the readable name first, then "表情".
    if (name.length >= 2 && name.startsWith('[') && name.endsWith(']')) {
      name = name.substring(1, name.length - 1).trim();
    }
    if (name.isEmpty) return null;
    return name.endsWith('表情') ? name : '$name表情';
  }

  void _syncNativeEmoteAccessibility() {
    final emotes = <Map<String, Object>>[];
    final signature = StringBuffer(controller.text);

    for (final item in controller.items) {
      if (item.type != RichTextType.emoji ||
          item.emote == null ||
          item.range.end != item.range.start + 1) {
        continue;
      }

      final label = _spokenEmoteName(item);
      if (label == null) continue;

      emotes.add(<String, Object>{
        'start': item.range.start,
        'label': label,
      });
      signature
        ..write('\u0000')
        ..write(item.range.start)
        ..write(':')
        ..write(label);
    }

    final nextSignature = signature.toString();
    if (_lastNativeEmoteSync == nextSignature) return;
    _lastNativeEmoteSync = nextSignature;

    _accessibilityChannel.invokeMethod<void>('setRichTextEmotes', <String, Object>{
      'text': controller.text,
      'emotes': emotes,
    }).ignore();
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);

    // Do not rely only on RenderEditable.hasFocus here. The semantics tree can
    // be described before the focused state reaches this renderer, while the
    // same configuration is then reused by VoiceOver. If this editor contains
    // image emotes, send their one-code-unit offsets immediately; while focused
    // we also sync an empty table after the last emote is removed.
    if (defaultTargetPlatform == TargetPlatform.iOS &&
        !obscureText &&
        (hasFocus || _usesA11yEmoteText)) {
      _syncNativeEmoteAccessibility();
    }

    if (!_usesA11yEmoteText) return;

    // WidgetSpan.toPlainText() contributes U+FFFC even though the controller's
    // logical text uses a normal one-code-unit emote placeholder. Expose the
    // controller text instead so the semantics value has the exact same length
    // and offsets as the real editing model.
    config.attributedValue = AttributedString(controller.text);
  }
}

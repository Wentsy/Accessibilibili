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
/// Image emotes remain exactly one U+FFFC object-replacement character in the
/// editing and semantics strings. iOS receives only a side table mapping those
/// one-unit offsets to concise emote names. Native accessibility can then name
/// the attachment without creating a second selection coordinate space.
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
    // The native attachment role already tells VoiceOver what kind of object
    // this is, so expose only the concise symbol name. Do not append "表情",
    // and strip it when a source token already contains that suffix.
    if (name.length >= 2 && name.startsWith('[') && name.endsWith(']')) {
      name = name.substring(1, name.length - 1).trim();
    }
    if (name.endsWith('表情')) {
      name = name.substring(0, name.length - 2).trim();
    }
    return name.isEmpty ? null : name;
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

    // Send attachment names whenever the renderer contains image emotes. Do not
    // rely solely on focus timing: the semantics configuration can be built
    // just before the focused state arrives on the renderer.
    if (defaultTargetPlatform == TargetPlatform.iOS &&
        !obscureText &&
        (hasFocus || _usesA11yEmoteText)) {
      _syncNativeEmoteAccessibility();
    }

    if (!_usesA11yEmoteText) return;

    // Keep semantics on the exact same one-code-unit text as the controller.
    // Never expand an emote name into this value: textSelection offsets must
    // stay valid for native start/end and character navigation.
    config.attributedValue = AttributedString(controller.text);
  }
}

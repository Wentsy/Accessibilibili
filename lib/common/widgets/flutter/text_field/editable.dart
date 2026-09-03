import 'dart:ui' show Locale;
import 'dart:ui' as ui show BoxHeightStyle, BoxWidthStyle;

import 'package:PiliPlus/common/widgets/flutter/text_field/controller.dart';
import 'package:PiliPlus/common/widgets/flutter/text_field/editable_base.dart'
    as base;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' hide RenderEditable;
import 'package:flutter/services.dart';

export 'package:PiliPlus/common/widgets/flutter/text_field/editable_base.dart'
    hide RenderEditable;

/// The original editable renderer remains in [base.RenderEditable].
///
/// Inline image emotes are painted as WidgetSpans, whose render-tree plain
/// text contains U+FFFC (Object Replacement Character). iOS VoiceOver exposes
/// that character as an "attachment" while editing. The editing controller,
/// however, now keeps a normal one-code-unit placeholder for image emotes.
///
/// Keep accessibility text on exactly the same one-code-unit-per-position
/// model as the real editing value. In particular, do not expand an emote into
/// a multi-character spoken label here: doing that gives VoiceOver and the
/// editor different offset spaces and breaks caret/end-of-field navigation.
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

  bool get _usesA11yEmoteText =>
      defaultTargetPlatform == TargetPlatform.iOS &&
      !obscureText &&
      controller.items.any(
        (item) => item.type == RichTextType.emoji && item.emote != null,
      );

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    if (!_usesA11yEmoteText) return;

    // WidgetSpan.toPlainText() contributes U+FFFC even though the controller's
    // logical text now uses a normal one-code-unit emote placeholder. Expose
    // the controller text instead so VoiceOver sees the same character count
    // as the actual editing model. Selection callbacks stay entirely native to
    // the base RenderEditable; there is deliberately no offset translation.
    config.attributedValue = AttributedString(controller.text);
  }
}
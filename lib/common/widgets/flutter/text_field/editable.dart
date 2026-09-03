import 'dart:ui' show Locale, PlatformDispatcher;
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

  RichTextItem? _imageEmoteStartingAt(int offset) {
    if (offset < 0) return null;
    for (final item in controller.items) {
      if (item.type == RichTextType.emoji &&
          item.emote != null &&
          item.range.start == offset) {
        return item;
      }
    }
    return null;
  }

  RichTextItem? _imageEmoteEndingAt(int offset) {
    if (offset < 0) return null;
    for (final item in controller.items) {
      if (item.type == RichTextType.emoji &&
          item.emote != null &&
          item.range.end == offset) {
        return item;
      }
    }
    return null;
  }

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

  void _announceEmote(RichTextItem? item) {
    if (item == null) return;
    final label = _spokenEmoteName(item);
    if (label == null) return;

    final view = PlatformDispatcher.instance.implicitView;
    if (view == null) return;
    SemanticsService.sendAnnouncement(view, label, textDirection).ignore();
  }

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

    // Let the base renderer move the real selection first, then override only
    // what VoiceOver speaks when that one-character step crosses an image
    // emote. The editor and accessibility selection therefore keep identical
    // offsets: one emote remains exactly one UTF-16 code unit.
    final moveForward = config.onMoveCursorForwardByCharacter;
    if (moveForward != null) {
      config.onMoveCursorForwardByCharacter = (bool extendSelection) {
        final offset = controller.selection.extentOffset;
        moveForward(extendSelection);
        _announceEmote(_imageEmoteStartingAt(offset));
      };
    }

    final moveBackward = config.onMoveCursorBackwardByCharacter;
    if (moveBackward != null) {
      config.onMoveCursorBackwardByCharacter = (bool extendSelection) {
        final offset = controller.selection.extentOffset;
        moveBackward(extendSelection);
        _announceEmote(_imageEmoteEndingAt(offset));
      };
    }
  }
}

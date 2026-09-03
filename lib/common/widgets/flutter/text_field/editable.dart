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
/// This thin wrapper only changes the iOS accessibility representation of
/// inline image emotes. The real editing value still contains a single U+FFFC
/// placeholder, so cursor movement, insertion and deletion keep the original
/// c974 behavior.
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

  _A11yTextMap _buildA11yTextMap() => _A11yTextMap(controller, plainText);

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    if (!_usesA11yEmoteText) return;

    final map = _buildA11yTextMap();
    config.attributedValue = AttributedString(map.spokenText);

    final currentSelection = selection;
    if (selectionEnabled && currentSelection != null && currentSelection.isValid) {
      config.textSelection = map.toA11ySelection(currentSelection);
    }

    if (hasFocus && selectionEnabled) {
      config.onSetSelection = (a11ySelection) {
        final realSelection = map.toRealSelection(
          a11ySelection,
          previousRealSelection: selection,
        );
        textSelectionDelegate.userUpdateTextEditingValue(
          textSelectionDelegate.textEditingValue.copyWith(
            selection: realSelection,
          ),
          SelectionChangedCause.keyboard,
        );
      };
    }
  }
}

class _A11yTextMap {
  _A11yTextMap(RichTextEditingController controller, String plainText) {
    final buffer = StringBuffer();
    var realCursor = 0;
    var a11yCursor = 0;

    void addPlain(int start, int end) {
      if (end <= start) return;
      final safeStart = start.clamp(0, plainText.length);
      final safeEnd = end.clamp(safeStart, plainText.length);
      final chunk = plainText.substring(safeStart, safeEnd);
      _segments.add(
        _A11ySegment(
          realStart: safeStart,
          realEnd: safeEnd,
          a11yStart: a11yCursor,
          a11yEnd: a11yCursor + chunk.length,
          isEmote: false,
        ),
      );
      buffer.write(chunk);
      a11yCursor += chunk.length;
    }

    for (final item in controller.items) {
      final start = item.range.start.clamp(0, plainText.length);
      final end = item.range.end.clamp(start, plainText.length);
      if (start > realCursor) {
        addPlain(realCursor, start);
      }

      final isImageEmote =
          item.type == RichTextType.emoji && item.emote != null;
      if (isImageEmote) {
        final label = _spokenEmoteLabel(item.rawText);
        _segments.add(
          _A11ySegment(
            realStart: start,
            realEnd: end,
            a11yStart: a11yCursor,
            a11yEnd: a11yCursor + label.length,
            isEmote: true,
          ),
        );
        buffer.write(label);
        a11yCursor += label.length;
      } else {
        addPlain(start, end);
      }
      realCursor = end;
    }

    if (realCursor < plainText.length) {
      addPlain(realCursor, plainText.length);
    }

    spokenText = buffer.toString();
    realLength = plainText.length;
  }

  final List<_A11ySegment> _segments = [];
  late final String spokenText;
  late final int realLength;

  static String _spokenEmoteLabel(String rawText) {
    var label = rawText.trim();
    if (label.length > 1 && label.startsWith('[') && label.endsWith(']')) {
      label = label.substring(1, label.length - 1).trim();
    }
    return label.isEmpty ? '表情' : '表情，$label';
  }

  int toA11yOffset(int realOffset) {
    final offset = realOffset.clamp(0, realLength);
    for (final segment in _segments) {
      if (offset < segment.realStart) break;
      if (offset <= segment.realEnd) {
        if (segment.isEmote) {
          return offset <= segment.realStart
              ? segment.a11yStart
              : segment.a11yEnd;
        }
        return segment.a11yStart + (offset - segment.realStart);
      }
    }
    return spokenText.length;
  }

  int toRealOffset(int a11yOffset, {int? previousRealOffset}) {
    final offset = a11yOffset.clamp(0, spokenText.length);
    for (final segment in _segments) {
      if (offset < segment.a11yStart) break;
      if (offset <= segment.a11yEnd) {
        if (segment.isEmote) {
          if (offset <= segment.a11yStart) return segment.realStart;
          if (offset >= segment.a11yEnd) return segment.realEnd;
          final previousA11y = previousRealOffset == null
              ? null
              : toA11yOffset(previousRealOffset);
          if (previousA11y != null) {
            return offset >= previousA11y
                ? segment.realEnd
                : segment.realStart;
          }
          final midpoint = (segment.a11yStart + segment.a11yEnd) / 2;
          return offset < midpoint ? segment.realStart : segment.realEnd;
        }
        return segment.realStart + (offset - segment.a11yStart);
      }
    }
    return realLength;
  }

  TextSelection toA11ySelection(TextSelection selection) {
    return TextSelection(
      baseOffset: toA11yOffset(selection.baseOffset),
      extentOffset: toA11yOffset(selection.extentOffset),
      affinity: selection.affinity,
      isDirectional: selection.isDirectional,
    );
  }

  TextSelection toRealSelection(
    TextSelection selection, {
    TextSelection? previousRealSelection,
  }) {
    final previousBase = previousRealSelection?.baseOffset;
    final previousExtent = previousRealSelection?.extentOffset;
    return TextSelection(
      baseOffset: toRealOffset(
        selection.baseOffset,
        previousRealOffset: previousBase,
      ),
      extentOffset: toRealOffset(
        selection.extentOffset,
        previousRealOffset: previousExtent,
      ),
      affinity: selection.affinity,
      isDirectional: selection.isDirectional,
    );
  }
}

class _A11ySegment {
  const _A11ySegment({
    required this.realStart,
    required this.realEnd,
    required this.a11yStart,
    required this.a11yEnd,
    required this.isEmote,
  });

  final int realStart;
  final int realEnd;
  final int a11yStart;
  final int a11yEnd;
  final bool isEmote;
}

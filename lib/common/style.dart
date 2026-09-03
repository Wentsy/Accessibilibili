import 'package:material_ui/material_ui.dart'
    show BorderRadius, Radius, BoxConstraints, ButtonStyle, VisualDensity;

abstract final class Style {
  static const cardSpace = 8.0;
  static const safeSpace = 12.0;
  static const mdRadius = BorderRadius.all(imgRadius);
  static const imgRadius = Radius.circular(10);
  static const aspectRatio = 16 / 10;
  static const aspectRatio16x9 = 16 / 9;
  static const imgMaxRatio = 2.6;
  static const bottomSheetRadius = BorderRadius.vertical(top: .circular(18));
  static const dialogFixedConstraints = BoxConstraints.tightFor(width: 420);
  static const topBarHeight = 52.0;
  static const buttonStyle = ButtonStyle(
    visualDensity: VisualDensity(horizontal: -2, vertical: -1.25),
    tapTargetSize: .shrinkWrap,
  );

  // Keep inline rich content as a single UTF-16 code unit so all existing
  // cursor/range bookkeeping stays unchanged. U+FFFC is the Unicode Object
  // Replacement Character, which iOS VoiceOver exposes as an "attachment"
  // while editing. A normal BMP symbol avoids that native attachment meaning;
  // the WidgetSpan still paints the real emote and rawText still stores the
  // server-side emote text.
  static const placeHolder = '\u263A';
}
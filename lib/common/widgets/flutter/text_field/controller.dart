import 'package:PiliPlus/common/widgets/flutter/text_field/controller_base.dart'
    as base;
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/models/common/image_type.dart';
import 'package:material_ui/material_ui.dart';

export 'package:PiliPlus/common/widgets/flutter/text_field/controller_base.dart'
    hide RichTextEditingController;

/// Keeps the original rich-text editing and selection behavior intact while
/// giving inline image emotes a meaningful accessibility label.
class RichTextEditingController extends base.RichTextEditingController {
  RichTextEditingController({super.items, super.onMention});

  String _emoteA11yLabel(base.RichTextItem item) {
    var label = item.rawText.trim();
    if (label.length > 1 && label.startsWith('[') && label.endsWith(']')) {
      label = label.substring(1, label.length - 1).trim();
    }
    return label.isEmpty ? '表情' : '表情，$label';
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    assert(
      !value.composing.isValid || !withComposing || value.isComposingRangeValid,
    );

    final bool composingRegionOutOfRange =
        !value.isComposingRangeValid || !withComposing;

    return TextSpan(
      style: style,
      children: items.map((e) {
        switch (e.type) {
          case base.RichTextType.text:
            return TextSpan(text: e.text);
          case base.RichTextType.composing:
            composingStyle ??=
                style?.merge(
                  const TextStyle(decoration: TextDecoration.underline),
                ) ??
                const TextStyle(decoration: TextDecoration.underline);
            if (composingRegionOutOfRange) {
              e.type = base.RichTextType.text;
            }
            return TextSpan(
              text: e.text,
              style: composingRegionOutOfRange ? null : composingStyle,
            );
          case base.RichTextType.at || base.RichTextType.common:
            richStyle ??= (style ?? const TextStyle()).copyWith(
              color: Theme.of(context).colorScheme.primary,
            );
            return TextSpan(text: e.text, style: richStyle);
          case base.RichTextType.emoji:
            final emote = e.emote;
            if (emote != null) {
              return WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Semantics(
                  label: _emoteA11yLabel(e),
                  child: ExcludeSemantics(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: NetworkImgLayer(
                        src: emote.url,
                        width: 22,
                        height: 22,
                        type: ImageType.emote,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              );
            }
            return TextSpan(text: e.text);
          case base.RichTextType.vote:
            richStyle ??= (style ?? const TextStyle()).copyWith(
              color: Theme.of(context).colorScheme.primary,
            );
            return TextSpan(
              children: [
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Icon(
                    Icons.bar_chart_rounded,
                    size: 22,
                    color: richStyle!.color,
                  ),
                ),
                TextSpan(text: '${e.rawText} ', style: richStyle),
              ],
            );
        }
      }).toList(),
    );
  }
}

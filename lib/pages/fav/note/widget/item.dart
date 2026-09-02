import 'package:PiliPlus/common/a11y/a11y_focus_scroll.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/select_mask.dart';
import 'package:PiliPlus/models_new/fav/fav_note/list.dart';
import 'package:PiliPlus/pages/fav/note/controller.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:flutter/semantics.dart';
import 'package:material_ui/material_ui.dart';

class FavNoteItem extends StatelessWidget {
  const FavNoteItem({
    super.key,
    required this.item,
    required this.ctr,
    required this.onSelect,
  });

  final FavNoteItemModel item;
  final FavNoteController ctr;
  final VoidCallback onSelect;

  void onLongPress() {
    if (!ctr.enableMultiSelect.value) {
      ctr.enableMultiSelect.value = true;
      onSelect();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final enableMultiSelect = ctr.enableMultiSelect.value;

    void onActivate() {
      if (enableMultiSelect) {
        onSelect();
        return;
      }
      if (item.webUrl?.isNotEmpty == true) {
        PageUtils.handleWebview(
          item.webUrl!,
          inApp: true,
        );
      }
    }

    final a11yLabel = [
      item.title ?? '未命名筆記',
      if (item.summary?.isNotEmpty == true) item.summary!,
      if (item.message?.isNotEmpty == true) item.message!,
    ].join('，');

    return Semantics(
      container: true,
      explicitChildNodes: false,
      excludeSemantics: true,
      button: item.webUrl?.isNotEmpty == true || enableMultiSelect,
      label: a11yLabel,
      hint: enableMultiSelect
          ? '點兩下選取或取消選取'
          : item.webUrl?.isNotEmpty == true
          ? '點兩下開啟筆記。上下滑有多選模式'
          : '上下滑有多選模式',
      onTap: onActivate,
      onDidGainAccessibilityFocus: () => a11yEnsureVisible(context),
      customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
        if (!enableMultiSelect)
          const CustomSemanticsAction(label: '多選模式'): onLongPress,
      },
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onActivate,
          onLongPress: onLongPress,
          onSecondaryTap: PlatformUtils.isMobile ? null : onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Style.safeSpace,
              vertical: 5,
            ),
            child: Row(
              spacing: 10,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.pic?.isNotEmpty == true)
                  AspectRatio(
                    aspectRatio: Style.aspectRatio,
                    child: LayoutBuilder(
                      builder: (context, boxConstraints) {
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            NetworkImgLayer(
                              src: item.pic,
                              width: boxConstraints.maxWidth,
                              height: boxConstraints.maxHeight,
                            ),
                            Positioned.fill(
                              child: selectMask(
                                colorScheme,
                                item.checked,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          height: 1.4,
                          fontSize: 14,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        item.summary ?? '',
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1,
                          color: colorScheme.outline,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        item.message ?? '',
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1,
                          color: colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

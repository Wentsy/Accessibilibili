import 'package:PiliPlus/common/a11y/a11y_focus_scroll.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/badge.dart';
import 'package:PiliPlus/common/widgets/button/icon_button.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/select_mask.dart';
import 'package:PiliPlus/models/common/badge_type.dart';
import 'package:PiliPlus/models_new/fav/fav_pgc/list.dart';
import 'package:PiliPlus/pages/common/multi_select/base.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:flutter/semantics.dart';
import 'package:material_ui/material_ui.dart';

class FavPgcItem extends StatelessWidget {
  const FavPgcItem({
    super.key,
    required this.item,
    required this.ctr,
    required this.onSelect,
    required this.onUpdateStatus,
  });

  final FavPgcItemModel item;
  final MultiSelectBase ctr;
  final VoidCallback onSelect;
  final VoidCallback onUpdateStatus;

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
      PageUtils.viewPgc(seasonId: item.seasonId);
    }

    final a11yLabel = [
      item.title ?? '未命名節目',
      if (item.badge?.isNotEmpty == true) item.badge!,
      if (item.newEp?.indexShow?.isNotEmpty == true) item.newEp!.indexShow!,
      if (item.isFinish == 0 && item.renewalTime?.isNotEmpty == true)
        item.renewalTime!,
      if (item.progress?.isNotEmpty == true) item.progress!,
    ].join('，');

    return Semantics(
      container: true,
      explicitChildNodes: false,
      excludeSemantics: true,
      button: true,
      label: a11yLabel,
      hint: enableMultiSelect
          ? '點兩下選取或取消選取'
          : '點兩下開啟。上下滑有更多操作與多選模式',
      onTap: onActivate,
      onDidGainAccessibilityFocus: () => a11yEnsureVisible(context),
      customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
        if (!enableMultiSelect)
          const CustomSemanticsAction(label: '更多操作'): onUpdateStatus,
        if (!enableMultiSelect)
          const CustomSemanticsAction(label: '多選模式'): onLongPress,
      },
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            InkWell(
              onTap: onActivate,
              onLongPress: onLongPress,
              onSecondaryTap: PlatformUtils.isMobile ? null : onLongPress,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Style.safeSpace,
                  vertical: 5,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AspectRatio(
                      aspectRatio: 3 / 4,
                      child: LayoutBuilder(
                        builder: (context, boxConstraints) {
                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              NetworkImgLayer(
                                src: item.cover,
                                width: boxConstraints.maxWidth,
                                height: boxConstraints.maxHeight,
                                borderRadius: const BorderRadius.all(
                                  Radius.circular(4),
                                ),
                              ),
                              PBadge(
                                right: 4,
                                top: 4,
                                text: item.badge,
                                size: PBadgeSize.small,
                                fontSize: 10,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                  vertical: 1,
                                ),
                              ),
                              Positioned.fill(
                                child: selectMask(
                                  colorScheme,
                                  item.checked,
                                  borderRadius: const BorderRadius.all(
                                    Radius.circular(4),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.title!),
                          if (item.newEp?.indexShow != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              '${item.newEp!.indexShow}${item.isFinish == 0 && item.renewalTime?.isNotEmpty == true ? '，${item.renewalTime}' : ''}',
                              style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                          if (item.progress != null) ...[
                            SizedBox(
                              height: item.newEp?.indexShow != null ? 2 : 6,
                            ),
                            Text(
                              item.progress!,
                              style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 12,
              bottom: 0,
              child: ExcludeSemantics(
                child: iconButton(
                  iconSize: 18,
                  onPressed: onUpdateStatus,
                  icon: const Icon(Icons.more_vert),
                  iconColor: colorScheme.outline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

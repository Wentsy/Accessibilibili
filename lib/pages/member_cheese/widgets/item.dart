import 'package:PiliPlus/common/a11y/a11y_focus_scroll.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/badge.dart';
import 'package:PiliPlus/common/widgets/button/icon_button.dart';
import 'package:PiliPlus/common/widgets/image/image_save.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/models_new/space/space_cheese/item.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:flutter/semantics.dart';
import 'package:material_ui/material_ui.dart';

class MemberCheeseItem extends StatelessWidget {
  const MemberCheeseItem({
    super.key,
    required this.item,
    this.onRemove,
  });

  final SpaceCheeseItem item;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final favTime = item.ctime != null
        ? DateFormatUtils.a11yDateFormat(int.parse(item.ctime!))
        : '';
    final a11yLabel = [
      item.title ?? '未命名課堂',
      if (item.status?.isNotEmpty == true) item.status!,
      if (item.marks?.isNotEmpty == true) item.marks!.join('，'),
      if (favTime.isNotEmpty) '$favTime收藏',
    ].join('，');

    void openItem() => PageUtils.viewPugv(seasonId: item.seasonId);
    void onLongPress() => imageSaveDialog(title: item.title, cover: item.cover);

    Widget child = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.title!,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (item.status != null) ...[
          const SizedBox(height: 6),
          Text(
            item.status!,
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (item.ctime != null) ...[
          const Spacer(),
          Text(
            '收藏于${DateFormatUtils.dateFormat(int.parse(item.ctime!))}',
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ],
    );
    if (onRemove != null) {
      child = Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          Positioned(
            right: 0,
            bottom: -8,
            child: ExcludeSemantics(
              child: iconButton(
                tooltip: '移除',
                onPressed: onRemove,
                icon: const Icon(Icons.clear),
                iconColor: theme.colorScheme.outline,
              ),
            ),
          ),
        ],
      );
    }

    return Semantics(
      container: true,
      explicitChildNodes: false,
      excludeSemantics: true,
      button: true,
      label: a11yLabel,
      hint: onRemove == null
          ? '點兩下開啟課堂'
          : '點兩下開啟課堂。上下滑有取消收藏',
      onTap: openItem,
      onDidGainAccessibilityFocus: () => a11yEnsureVisible(context),
      customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
        if (onRemove != null)
          const CustomSemanticsAction(label: '取消收藏'): onRemove!,
      },
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: openItem,
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
                  aspectRatio: Style.aspectRatio,
                  child: LayoutBuilder(
                    builder: (context, boxConstraints) {
                      Widget cover = NetworkImgLayer(
                        src: item.cover,
                        width: boxConstraints.maxWidth,
                        height: boxConstraints.maxHeight,
                        borderRadius: const BorderRadius.all(
                          Radius.circular(4),
                        ),
                      );
                      if (item.marks?.isNotEmpty == true) {
                        cover = Stack(
                          clipBehavior: Clip.none,
                          children: [
                            cover,
                            PBadge(
                              right: 6,
                              top: 6,
                              text: item.marks!.join('|'),
                            ),
                          ],
                        );
                      }
                      return cover;
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

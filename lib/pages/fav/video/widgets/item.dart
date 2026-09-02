import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/image/image_save.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/models_new/fav/fav_folder/list.dart';
import 'package:PiliPlus/utils/bili_utils.dart';
import 'package:flutter/semantics.dart';
import 'package:material_ui/material_ui.dart';

class FavVideoItem extends StatelessWidget {
  final String heroTag;
  final FavFolderInfo item;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const FavVideoItem({
    super.key,
    this.onTap,
    this.onLongPress,
    required this.heroTag,
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    final defaultLongPress = onTap == null
        ? null
        : () => imageSaveDialog(
            title: item.title,
            cover: item.cover,
          );
    final longPressAction = onLongPress ?? defaultLongPress;
    final intro = item.intro?.trim();
    final a11yLabel = [
      item.title,
      if (intro?.isNotEmpty == true) intro!,
      '${item.mediaCount}個內容',
      BiliUtils.isPublicFavText(item.attr),
    ].join('，');

    return Semantics(
      container: true,
      explicitChildNodes: false,
      excludeSemantics: true,
      button: onTap != null,
      label: a11yLabel,
      hint: onTap == null ? null : '點兩下開啟收藏夾',
      onTap: onTap,
      customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
        if (longPressAction != null)
          const CustomSemanticsAction(label: '更多操作'): longPressAction,
      },
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          onLongPress: longPressAction,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: Style.aspectRatio,
                  child: LayoutBuilder(
                    builder: (context, boxConstraints) {
                      return Hero(
                        tag: heroTag,
                        child: NetworkImgLayer(
                          src: item.cover,
                          width: boxConstraints.maxWidth,
                          height: boxConstraints.maxHeight,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
                content(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget content(BuildContext context) {
    final theme = Theme.of(context);
    final fontSize = theme.textTheme.labelMedium!.fontSize;
    final color = theme.colorScheme.outline;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.title,
            textAlign: TextAlign.start,
            style: const TextStyle(
              letterSpacing: 0.3,
            ),
          ),
          if (item.intro?.isNotEmpty == true)
            Text(
              item.intro!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: fontSize,
                color: color,
              ),
            ),
          Text(
            '${item.mediaCount}个内容',
            style: TextStyle(
              fontSize: fontSize,
              color: color,
            ),
          ),
          const Spacer(),
          Text(
            BiliUtils.isPublicFavText(item.attr),
            style: TextStyle(
              fontSize: fontSize,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

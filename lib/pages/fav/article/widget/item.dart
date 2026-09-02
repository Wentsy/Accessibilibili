import 'package:PiliPlus/common/a11y/a11y_focus_scroll.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/button/icon_button.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/stat/stat.dart';
import 'package:PiliPlus/models/common/stat_type.dart';
import 'package:PiliPlus/models_new/fav/fav_article/item.dart';
import 'package:flutter/semantics.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class FavArticleItem extends StatelessWidget {
  const FavArticleItem({
    super.key,
    required this.item,
    required this.onDelete,
  });

  final FavArticleItemModel item;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    void openArticle() => Get.toNamed(
      '/articlePage',
      parameters: {
        'id': item.opusId!.toString(),
        'type': 'opus',
      },
    );

    final a11yLabel = [
      item.content ?? '未命名文章',
      if (item.author?.name?.isNotEmpty == true) item.author!.name!,
      if (item.stat?.like != null) '讚 ${item.stat!.like}',
      if (item.pubTime?.isNotEmpty == true) item.pubTime!,
    ].join('，');

    return Semantics(
      container: true,
      explicitChildNodes: false,
      excludeSemantics: true,
      button: true,
      label: a11yLabel,
      hint: '點兩下開啟文章。上下滑有取消收藏',
      onTap: openArticle,
      onDidGainAccessibilityFocus: () => a11yEnsureVisible(context),
      customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
        const CustomSemanticsAction(label: '取消收藏'): onDelete,
      },
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            InkWell(
              onTap: openArticle,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Style.safeSpace,
                  vertical: 5,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (item.cover != null) ...[
                      AspectRatio(
                        aspectRatio: Style.aspectRatio,
                        child: LayoutBuilder(
                          builder: (context, boxConstraints) {
                            return NetworkImgLayer(
                              src: item.cover!.url,
                              width: boxConstraints.maxWidth,
                              height: boxConstraints.maxHeight,
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              item.content!,
                              style: TextStyle(
                                fontSize: theme.textTheme.bodyMedium!.fontSize,
                                height: 1.42,
                                letterSpacing: 0.3,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            item.author!.name!,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1,
                              color: theme.colorScheme.outline,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              StatWidget(
                                type: StatType.like,
                                value: item.stat!.like,
                                color: theme.colorScheme.outline,
                              ),
                              Text(
                                '  ·  ${item.pubTime}',
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1,
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 12,
              bottom: -6,
              child: ExcludeSemantics(
                child: iconButton(
                  iconSize: 18,
                  onPressed: onDelete,
                  icon: const Icon(Icons.clear),
                  iconColor: theme.colorScheme.outline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

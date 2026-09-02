import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/badge.dart';
import 'package:PiliPlus/common/widgets/image/image_save.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/models_new/sub/sub/list.dart';
import 'package:PiliPlus/pages/subscription_detail/view.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:flutter/semantics.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

class SubItem extends StatelessWidget {
  final SubItemModel item;
  final VoidCallback cancelSub;
  const SubItem({
    super.key,
    required this.item,
    required this.cancelSub,
  });

  @override
  Widget build(BuildContext context) {
    String heroTag = Utils.makeHeroTag(item.id);
    final type = switch (item.type) {
      11 => '收藏夾',
      21 => '合集',
      _ => '其它(${item.type})',
    };
    final isInvalid = item.state == 1;
    final title = item.title ?? type;
    final upperName = item.upper?.name;
    final mediaCount = item.mediaCount ?? 0;
    final a11yLabel = [
      title,
      if (upperName?.isNotEmpty == true) 'UP主 $upperName',
      '$mediaCount個影片',
      type,
      if (isInvalid) '已失效',
    ].join('，');

    void openItem() {
      if (isInvalid) {
        SmartDialog.showToast('該$type已失效');
        return;
      }
      if (item.type == 11) {
        Get.toNamed(
          '/favDetail',
          parameters: {
            'mediaId': item.id!.toString(),
            'heroTag': heroTag,
          },
        );
      } else {
        SubDetailPage.toSubDetailPage(
          item.id!,
          heroTag: heroTag,
          subInfo: item,
        );
      }
    }

    void onLongPress() => imageSaveDialog(
      title: item.title,
      cover: item.cover,
    );

    return Semantics(
      container: true,
      explicitChildNodes: false,
      excludeSemantics: true,
      button: true,
      label: a11yLabel,
      hint: isInvalid
          ? '此訂閱已失效。上滑有取消訂閱'
          : '點兩下開啟。上滑有取消訂閱',
      onTap: openItem,
      customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
        const CustomSemanticsAction(label: '取消訂閱'): cancelSub,
      },
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: openItem,
          onLongPress: onLongPress,
          onSecondaryTap: PlatformUtils.isMobile ? null : onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: Style.aspectRatio,
                  child: LayoutBuilder(
                    builder: (context, boxConstraints) {
                      double maxWidth = boxConstraints.maxWidth;
                      double maxHeight = boxConstraints.maxHeight;
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Hero(
                            tag: heroTag,
                            child: NetworkImgLayer(
                              src: item.cover,
                              width: maxWidth,
                              height: maxHeight,
                            ),
                          ),
                          PBadge(
                            right: 6,
                            top: 6,
                            text: type,
                          ),
                        ],
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
    final style = TextStyle(
      fontSize: 13,
      color: theme.colorScheme.outline,
    );
    return Expanded(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  item.title!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.start,
                  style: const TextStyle(
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              Text(
                'UP主: ${item.upper!.name!}',
                textAlign: TextAlign.start,
                style: style,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                '${item.mediaCount}個影片',
                textAlign: TextAlign.start,
                style: style,
              ),
            ],
          ),
          Positioned(
            bottom: 0,
            right: 0,
            height: 35,
            width: 35,
            child: IconButton(
              tooltip: '取消訂閱',
              onPressed: cancelSub,
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.outline,
                padding: EdgeInsets.zero,
              ),
              icon: const Icon(Icons.delete_outline, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

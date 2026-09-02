import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/badge.dart';
import 'package:PiliPlus/common/widgets/button/icon_button.dart';
import 'package:PiliPlus/common/widgets/image/image_save.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/select_mask.dart';
import 'package:PiliPlus/common/widgets/stat/stat.dart';
import 'package:PiliPlus/grpc/bilibili/app/listener/v1.pbenum.dart'
    show PlaylistSource;
import 'package:PiliPlus/models/common/badge_type.dart';
import 'package:PiliPlus/models/common/stat_type.dart';
import 'package:PiliPlus/models_new/fav/fav_detail/media.dart';
import 'package:PiliPlus/pages/audio/view.dart';
import 'package:PiliPlus/pages/fav_detail/controller.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:flutter/semantics.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

// 收藏视频卡片 - 水平布局
class FavVideoCardH extends StatelessWidget {
  final FavDetailItemModel item;
  final int? index;
  final BaseFavController? ctr;

  const FavVideoCardH({
    super.key,
    required this.item,
    this.index,
    this.ctr,
  }) : assert(ctr == null || index != null);

  bool get isSort => ctr == null;

  @override
  Widget build(BuildContext context) {
    final isOwner = !isSort && ctr!.isOwner;
    late final enableMultiSelect = ctr?.enableMultiSelect.value ?? false;
    final colorScheme = ColorScheme.of(context);

    final onLongPress = isSort || enableMultiSelect
        ? null
        : isOwner && !enableMultiSelect
        ? () {
            ctr!
              ..enableMultiSelect.value = true
              ..onSelect(item);
          }
        : () => imageSaveDialog(
            title: item.title,
            cover: item.cover,
            bvid: item.bvid,
          );

    void onActivate() {
      if (enableMultiSelect) {
        ctr!.onSelect(item);
        return;
      }
      if (!const [0, 16].contains(item.attr)) {
        Get.toNamed('/member?mid=${item.upper?.mid}');
        return;
      }

      switch (item.type) {
        case 12:
          AudioPage.toAudioPage(
            oid: item.id!,
            itemType: 3,
            from: PlaylistSource.AUDIO_CARD,
          );
          break;
        case 24:
          PageUtils.viewPgc(
            seasonId: item.ogv!.seasonId,
            epId: item.id,
          );
          break;
        default:
          ctr!.onViewFav(item, index);
          break;
      }
    }

    void cancelFav() {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('提示'),
          content: const Text('要取消收藏嗎?'),
          actions: [
            TextButton(
              onPressed: Get.back,
              child: Text(
                '取消',
                style: TextStyle(color: colorScheme.outline),
              ),
            ),
            TextButton(
              onPressed: () {
                Get.back();
                ctr!.onCancelFav(index!, item.id!, item.type!);
              },
              child: const Text('確定取消'),
            ),
          ],
        ),
      );
    }

    final duration = DurationUtils.formatDuration(item.duration);
    final favTime = DateFormatUtils.a11yDateFormat(item.favTime);
    final a11yLabel = [
      item.title ?? '未命名收藏內容',
      if (item.upper?.name?.isNotEmpty == true) 'UP主 ${item.upper!.name}',
      if (duration.isNotEmpty) '時長 $duration',
      if (item.cntInfo?.play != null) '播放 ${item.cntInfo!.play}',
      if (item.cntInfo?.danmaku != null) '彈幕 ${item.cntInfo!.danmaku}',
      if (favTime.isNotEmpty) '$favTime收藏',
    ].join('，');

    return Semantics(
      container: true,
      explicitChildNodes: false,
      excludeSemantics: true,
      button: !isSort,
      label: a11yLabel,
      hint: isSort
          ? null
          : isOwner && !enableMultiSelect
          ? '點兩下開啟。上滑有取消收藏'
          : '點兩下開啟',
      onTap: isSort ? null : onActivate,
      customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
        if (isOwner && !enableMultiSelect)
          const CustomSemanticsAction(label: '取消收藏'): cancelFav,
      },
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: isSort ? null : onActivate,
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
                      double maxWidth = boxConstraints.maxWidth;
                      double maxHeight = boxConstraints.maxHeight;
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          NetworkImgLayer(
                            src: item.cover,
                            width: maxWidth,
                            height: maxHeight,
                          ),
                          PBadge(
                            text: DurationUtils.formatDuration(item.duration),
                            right: 6.0,
                            bottom: 6.0,
                            type: PBadgeType.gray,
                          ),
                          if (item.type == 12)
                            const PBadge(
                              text: '音频',
                              top: 6.0,
                              right: 6.0,
                              type: PBadgeType.gray,
                            )
                          else
                            PBadge(
                              text: item.ogv?.typeName,
                              top: 6.0,
                              right: 6.0,
                              bottom: null,
                              left: null,
                            ),
                          if (!isSort)
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
                const SizedBox(width: 10),
                content(context, colorScheme, isOwner, cancelFav),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget content(
    BuildContext context,
    ColorScheme colorScheme,
    bool isOwner,
    VoidCallback cancelFav,
  ) {
    return Expanded(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            spacing: 3,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title!,
                textAlign: TextAlign.start,
                style: const TextStyle(
                  letterSpacing: 0.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (item.type == 24 && item.intro?.isNotEmpty == true)
                Text(
                  item.intro!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.outline,
                  ),
                ),
              const Spacer(),
              Text(
                '${DateFormatUtils.dateFormat(item.favTime)} ${item.upper?.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  height: 1,
                  fontSize: 12,
                  color: colorScheme.outline,
                ),
              ),
              if (item.type != 24)
                Row(
                  spacing: 8,
                  children: [
                    StatWidget(
                      type: StatType.play,
                      value: item.cntInfo?.play,
                    ),
                    StatWidget(
                      type: StatType.danmaku,
                      value: item.cntInfo?.danmaku,
                    ),
                  ],
                ),
            ],
          ),
          if (isOwner)
            Positioned(
              right: 0,
              bottom: -8,
              child: iconButton(
                icon: const Icon(Icons.clear),
                tooltip: '取消收藏',
                iconColor: colorScheme.outline,
                onPressed: cancelFav,
              ),
            ),
        ],
      ),
    );
  }
}

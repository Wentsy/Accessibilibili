import 'package:flutter/semantics.dart' show CustomSemanticsAction, OrdinalSortKey;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/badge.dart';
import 'package:PiliPlus/common/widgets/image/image_save.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/progress_bar/video_progress_indicator.dart';
import 'package:PiliPlus/common/widgets/stat/stat.dart';
import 'package:PiliPlus/common/widgets/video_popup_menu.dart';
import 'package:PiliPlus/models/common/badge_type.dart';
import 'package:PiliPlus/models/common/stat_type.dart';
import 'package:PiliPlus/models_new/space/space_archive/item.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/extension/dimension_ext.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:material_ui/material_ui.dart';

class VideoCardHMemberVideo extends StatelessWidget {
  const VideoCardHMemberVideo({
    super.key,
    required this.videoItem,
    this.onTap,
    this.bvid,
    this.fromViewAid,
    this.a11ySortKey,
  });
  final SpaceArchiveItem videoItem;
  final VoidCallback? onTap;
  final dynamic bvid;
  final String? fromViewAid;
  final OrdinalSortKey? a11ySortKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    void onLongPress() => imageSaveDialog(
      title: videoItem.title,
      cover: videoItem.cover,
      bvid: videoItem.bvid,
    );
    final bvid = videoItem.bvid;
    return Semantics(
      container: true,
      explicitChildNodes: false,
      excludeSemantics: true,
      sortKey: a11ySortKey,
      label: '${videoItem.title}，播放 ${videoItem.stat?.view ?? "?"} 次',
      hint: '點兩下開啟影片。上滑有更多操作',
      customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
        CustomSemanticsAction(label: '分享'): () {
          if (bvid?.isNotEmpty != true) return;
          Utils.copyText('https://www.bilibili.com/video/$bvid');
          SmartDialog.showToast('連結已複製，可直接分享');
        },
      },
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            InkWell(
              onTap:
                  onTap ??
                  () {
                    final isPgc = videoItem.isPgc == true;
                    final isPugv = videoItem.isPugv == true;
                    if ((isPgc || isPugv) && videoItem.uri?.isNotEmpty == true) {
                      if (PageUtils.viewPgcFromUri(
                        videoItem.uri!,
                        isPgc: isPgc,
                      )) {
                        return;
                      }
                    }
                    if (videoItem.bvid == null || videoItem.cid == null) {
                      return;
                    }
                    bool isVertical = false;
                    if (videoItem.uri case final uri?) {
                      isVertical = uri.isVerticalFromUri;
                    }
                    PageUtils.toVideoPage(
                      bvid: videoItem.bvid,
                      cid: videoItem.cid!,
                      cover: videoItem.cover,
                      title: videoItem.title,
                      isVertical: isVertical,
                    );
                  },
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
                          final double maxWidth = boxConstraints.maxWidth;
                          final double maxHeight = boxConstraints.maxHeight;
                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              NetworkImgLayer(
                                src: videoItem.cover,
                                width: maxWidth,
                                height: maxHeight,
                              ),
                              if (fromViewAid == videoItem.param)
                                const Positioned.fill(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      borderRadius: Style.mdRadius,
                                      color: Colors.black54,
                                    ),
                                    child: Center(
                                      child: Text(
                                        '上次观看',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 15,
                                          letterSpacing: 5,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              if (videoItem.badges?.isNotEmpty == true)
                                PBadge(
                                  text: videoItem.badges!
                                      .map((item) => item.text)
                                      .join('|'),
                                  right: 6.0,
                                  top: 6.0,
                                  type: videoItem.badges!.first.text == '充電專屬'
                                      ? PBadgeType.error
                                      : PBadgeType.primary,
                                ),
                              if (videoItem.history != null) ...[
                                Builder(
                                  builder: (context) {
                                    try {
                                      return Positioned(
                                        left: 0,
                                        right: 0,
                                        bottom: 0,
                                        child: VideoProgressIndicator(
                                          color: theme.colorScheme.primary,
                                          backgroundColor: theme
                                              .colorScheme.secondaryContainer,
                                          progress:
                                              videoItem.history!.progress! /
                                              videoItem.history!.duration!,
                                        ),
                                      );
                                    } catch (_) {
                                      return const SizedBox.shrink();
                                    }
                                  },
                                ),
                                Builder(
                                  builder: (context) {
                                    try {
                                      return PBadge(
                                        text: videoItem.history!.progress ==
                                                videoItem.history!.duration
                                            ? '已看完'
                                            : '${DurationUtils.formatDuration(videoItem.history!.progress)}/${DurationUtils.formatDuration(videoItem.history!.duration)}',
                                        right: 6.0,
                                        bottom: 6.0,
                                        type: PBadgeType.gray,
                                      );
                                    } catch (_) {
                                      return PBadge(
                                        text: DurationUtils.formatDuration(
                                          videoItem.duration,
                                        ),
                                        right: 6.0,
                                        bottom: 6.0,
                                        type: PBadgeType.gray,
                                      );
                                    }
                                  },
                                ),
                              ] else if (videoItem.duration > 0)
                                PBadge(
                                  text: DurationUtils.formatDuration(
                                    videoItem.duration,
                                  ),
                                  right: 6.0,
                                  bottom: 6.0,
                                  type: PBadgeType.gray,
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    content(context, theme),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget content(BuildContext context, ThemeData theme) {
    final isCurr =
        fromViewAid == videoItem.param ||
        (videoItem.bvid != null && videoItem.bvid == bvid);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              videoItem.title,
              textAlign: TextAlign.start,
              style: TextStyle(
                fontWeight: isCurr ? FontWeight.bold : null,
                fontSize: theme.textTheme.bodyMedium!.fontSize,
                height: 1.42,
                letterSpacing: 0.3,
                color: isCurr ? theme.colorScheme.primary : null,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            videoItem.season != null
                ? DateFormatUtils.dateFormat(videoItem.season!.mtime)
                : videoItem.publishTimeText ?? '',
            maxLines: 1,
            style: TextStyle(
              fontSize: 12,
              height: 1,
              color: theme.colorScheme.outline,
              overflow: TextOverflow.clip,
            ),
          ),
          const SizedBox(height: 3),
          Row(
            spacing: 8,
            children: [
              StatWidget(
                type: StatType.play,
                value: videoItem.stat.view,
              ),
              StatWidget(
                type: StatType.danmaku,
                value: videoItem.stat.danmu,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/a11y/a11y_focus_scroll.dart';
import 'package:PiliPlus/common/widgets/badge.dart';
import 'package:PiliPlus/common/widgets/image/image_save.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/stat/stat.dart';
import 'package:PiliPlus/common/widgets/video_popup_menu.dart';
import 'package:PiliPlus/http/search.dart';
import 'package:PiliPlus/http/user.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:flutter/foundation.dart';
import 'dart:ui' as ui;
import 'package:flutter/semantics.dart';
import 'package:PiliPlus/models/home/rcmd/result.dart';
import 'package:PiliPlus/models/model_rec_video_item.dart';
import 'package:PiliPlus/models_new/video/video_detail/dimension.dart';
import 'package:PiliPlus/utils/app_scheme.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/extension/dimension_ext.dart';
import 'package:PiliPlus/utils/id_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

// 视频卡片 - 垂直布局
class VideoCardV extends StatelessWidget {
  final BaseRcmdVideoItemModel videoItem;
  final VoidCallback? onRemove;

  const VideoCardV({
    super.key,
    required this.videoItem,
    this.onRemove,
  });

  Future<void> onPushDetail() async {
    switch (videoItem.goto) {
      case 'bangumi':
        PageUtils.viewPgc(epId: videoItem.param!);
        break;
      case 'av':
        var bvid = videoItem.bvid ?? IdUtils.av2bv(videoItem.aid!);
        var cid = videoItem.cid;
        bool isVertical = false;
        Dimension? dimension;
        if (videoItem is RcmdVideoItemAppModel) {
          if (videoItem.uri case final uri?) {
            isVertical = uri.isVerticalFromUri;
          }
        }
        if (cid == null) {
          if (await SearchHttp.ab2cWithDimension(aid: videoItem.aid, bvid: bvid)
              case final res?) {
            cid = res.cid;
            dimension = res.dimension;
          }
        }
        if (cid != null) {
          PageUtils.toVideoPage(
            aid: videoItem.aid,
            bvid: bvid,
            cid: cid,
            cover: videoItem.cover,
            title: videoItem.title,
            isVertical: isVertical,
            dimension: dimension,
          );
        }
        break;
      // 动态
      case 'picture':
        try {
          PiliScheme.routePushFromUrl(videoItem.uri!);
        } catch (err) {
          SmartDialog.showToast(err.toString());
        }
        break;
      default:
        if (videoItem.uri?.isNotEmpty == true) {
          PiliScheme.routePushFromUrl(videoItem.uri!);
        }
    }
  }

  /// 無障礙自訂操作：VoiceOver 上下滑切換、點兩下啟用
  Map<CustomSemanticsAction, VoidCallback> _a11yActions(BuildContext context) {
    final bvid = videoItem.bvid;
    return <CustomSemanticsAction, VoidCallback>{
      CustomSemanticsAction(label: '點讚'): () async {
        if (bvid == null) return;
        final res = await VideoHttp.likeVideo(bvid: bvid, type: true);
        if (res case Success(:final response)) {
          SmartDialog.showToast(response);
          // 🔴 語音反饋：VoiceOver 立即朗讀結果
          SemanticsService.sendAnnouncement(
              WidgetsBinding.instance.platformDispatcher.views.first,
              response,
              ui.TextDirection.ltr);
        } else {
          SmartDialog.showToast('點讚失敗（需登入）');
          SemanticsService.sendAnnouncement(
              WidgetsBinding.instance.platformDispatcher.views.first,
              '點讚失敗，需要登入',
              ui.TextDirection.ltr);
        }
      },
      CustomSemanticsAction(label: '分享'): () {
        if (bvid == null) return;
        Utils.copyText('https://www.bilibili.com/video/$bvid');
        SmartDialog.showToast('連結已複製，可直接分享');
      },
      CustomSemanticsAction(label: '稍後再看'): () {
        if (bvid == null || !Accounts.main.isLogin) {
          SmartDialog.showToast('稍後再看需登入');
          return;
        }
        UserHttp.toViewLater(bvid: bvid);
      },
      CustomSemanticsAction(label: '造訪UP主'): () {
        Get.toNamed('/member?mid=${videoItem.owner.mid}');
      },
      CustomSemanticsAction(label: '更多操作'): () {
        showModalBottomSheet(
          context: context,
          useSafeArea: true,
          builder: (sheetCtx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.link),
                  title: const Text('複製影片連結'),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    if (bvid != null) {
                      Utils.copyText('https://www.bilibili.com/video/$bvid');
                      SmartDialog.showToast('連結已複製');
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.person_search),
                  title: Text('造訪UP主：${videoItem.owner.name}'),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    Get.toNamed('/member?mid=${videoItem.owner.mid}');
                  },
                ),
              ],
            ),
          ),
        );
      },
    };
  }

  @override
  Widget build(BuildContext context) {
    void onLongPress() => imageSaveDialog(
      title: videoItem.title,
      cover: videoItem.cover,
      bvid: videoItem.bvid,
    );
    // 🔴 無障礙改造：整卡一個語義節點，VoiceOver 左右滑逐卡瀏覽
    // 標題+UP主+時長一次唸完；上下滑 = 點讚/分享/更多 操作
    final durationPart = videoItem.duration > 0
        ? '，時長 ${DurationUtils.formatDuration(videoItem.duration)}'
        : '';
    final pubdate = DateFormatUtils.dateFormat(
      videoItem.pubdate,
      short: shortFormat,
      long: longFormat,
    );
    final pubdatePart = pubdate.isNotEmpty ? '，發布時間 $pubdate' : '';
    final String a11yLabel =
        '${videoItem.title}，${videoItem.owner.name}$durationPart'
        '，播放 ${videoItem.stat.view} 次，彈幕 ${videoItem.stat.danmu}$pubdatePart';
    return Semantics(
      container: true,
      explicitChildNodes: false,
      excludeSemantics: true,
      button: false,
      label: a11yLabel,
      hint: '點兩下開啟影片。上滑有更多操作',
      onLongPressHint: null,
      onDidGainAccessibilityFocus: () => a11yEnsureVisible(context),
      customSemanticsActions: _a11yActions(context),
      child: ExcludeSemantics(
      child: Stack(
        clipBehavior: Clip.none,
      children: [
        Card(
          child: InkWell(
            onTap: onPushDetail,
            borderRadius: const .all(.circular(12)),
            child: Column(
              crossAxisAlignment: .start,
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
                            src: videoItem.cover,
                            width: maxWidth,
                            height: maxHeight,
                            borderRadius: const .vertical(top: .circular(12)),
                          ),
                          if (videoItem.duration > 0)
                            PBadge(
                              bottom: 6,
                              right: 7,
                              size: .small,
                              type: .gray,
                              text: DurationUtils.formatDuration(
                                videoItem.duration,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                content(context),
              ],
            ),
          ),
        ),
      ],
      ),
      ),
    );
  }

  Widget content(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Padding(
        padding: const .fromLTRB(6, 5, 6, 5),
        child: Column(
          crossAxisAlignment: .start,
          children: [
            Expanded(
              child: Text(
                videoItem.title,
                maxLines: 2,
                overflow: .ellipsis,
                style: const TextStyle(height: 1.38),
              ),
            ),
            videoStat(theme),
            Row(
              spacing: 2,
              children: [
                if (videoItem.goto == 'bangumi')
                  PBadge(
                    text: videoItem.pgcBadge,
                    isStack: false,
                    size: .small,
                    type: .line_primary,
                    fontSize: 9,
                  ),
                if (videoItem.rcmdReason != null)
                  PBadge(
                    text: videoItem.rcmdReason,
                    isStack: false,
                    size: .small,
                    type: .secondary,
                  ),
                if (videoItem.goto == 'picture')
                  const PBadge(
                    text: '动态',
                    isStack: false,
                    size: .small,
                    type: .line_primary,
                    fontSize: 9,
                  ),
                if (videoItem.isFollowed)
                  const PBadge(
                    text: '已关注',
                    isStack: false,
                    size: .small,
                    type: .secondary,
                  ),
                Expanded(
                  flex: 1,
                  child: Text(
                    videoItem.owner.name.toString(),
                    maxLines: 1,
                    overflow: .clip,
                    semanticsLabel: 'UP：${videoItem.owner.name}',
                    style: TextStyle(
                      height: 1.5,
                      fontSize: theme.textTheme.labelMedium!.fontSize,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
                if (videoItem.goto == 'av') const SizedBox(width: 10),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static final shortFormat = DateFormat('M-d');
  static final longFormat = DateFormat('yy-M-d');

  Widget videoStat(ThemeData theme) {
    return Row(
      children: [
        StatWidget(
          type: .play,
          value: videoItem.stat.view,
        ),
        if (videoItem.goto != 'picture') ...[
          const SizedBox(width: 4),
          StatWidget(
            type: .danmaku,
            value: videoItem.stat.danmu,
          ),
        ],
        if (videoItem is RcmdVideoItemModel) ...[
          const Spacer(),
          Text.rich(
            maxLines: 1,
            TextSpan(
              style: TextStyle(
                fontSize: theme.textTheme.labelSmall!.fontSize,
                color: theme.colorScheme.outline.withValues(alpha: 0.8),
              ),
              text: DateFormatUtils.dateFormat(
                videoItem.pubdate,
                short: shortFormat,
                long: longFormat,
              ),
            ),
          ),
          const SizedBox(width: 2),
        ],
      ],
    );
  }
}

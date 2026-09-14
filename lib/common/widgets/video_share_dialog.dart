import 'package:PiliPlus/http/constants.dart';
import 'package:PiliPlus/pages/dynamics_repost/view.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/share_utils.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

/// 顯示與影片播放頁「分享」按鈕相同內容的分享對話框。
///
/// VoiceOver 自訂動作的 widget context 有時不掛在可推 dialog 的 Navigator 下，
/// 因此優先使用 Get.context（目前 App 的頁面 context），避免上下滑「分享」無反應。
void showVideoShareDialog({
  required BuildContext context,
  required String bvid,
  int? aid,
  required String title,
  String? cover,
  String? ownerName,
  int? ownerMid,
  String playedTimePos = '',
}) {
  if (bvid.isEmpty) return;

  final activeContext = Get.context ?? context;
  final videoUrl = '${HttpString.baseUrl}/video/$bvid';
  final isLogin = Accounts.main.isLogin;

  showDialog<void>(
    context: activeContext,
    builder: (_) => SimpleDialog(
      clipBehavior: Clip.hardEdge,
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        ListTile(
          dense: true,
          title: const Text(
            '复制链接',
            style: TextStyle(fontSize: 14),
          ),
          onTap: () {
            Get.back();
            Utils.copyText(videoUrl);
          },
          trailing: playedTimePos.isNotEmpty
              ? IconButton(
                  tooltip: '精确分享',
                  icon: const Icon(Icons.timer_outlined),
                  onPressed: () {
                    Get.back();
                    Utils.copyText('$videoUrl$playedTimePos');
                  },
                )
              : null,
        ),
        ListTile(
          dense: true,
          title: const Text(
            '其它app打开',
            style: TextStyle(fontSize: 14),
          ),
          onTap: () {
            Get.back();
            PageUtils.launchURL(videoUrl);
          },
        ),
        if (PlatformUtils.isMobile)
          ListTile(
            dense: true,
            title: const Text(
              '分享视频',
              style: TextStyle(fontSize: 14),
            ),
            onTap: () {
              Get.back();
              ShareUtils.shareText(
                '$title UP主: ${ownerName ?? ''} - $videoUrl',
              );
            },
          ),
        if (isLogin && aid != null)
          ListTile(
            dense: true,
            title: const Text(
              '分享至动态',
              style: TextStyle(fontSize: 14),
            ),
            onTap: () {
              Get.back();
              showModalBottomSheet(
                context: activeContext,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (context) => RepostPanel(
                  rid: aid,
                  dynType: 8,
                  pic: cover,
                  title: title,
                  uname: ownerName,
                ),
              );
            },
          ),
        if (isLogin && aid != null && ownerMid != null)
          ListTile(
            dense: true,
            title: const Text(
              '分享至消息',
              style: TextStyle(fontSize: 14),
            ),
            onTap: () {
              Get.back();
              try {
                PageUtils.pmShare(
                  activeContext,
                  content: {
                    'id': aid.toString(),
                    'title': title,
                    'headline': title,
                    'source': 5,
                    'thumb': cover ?? '',
                    'author': ownerName ?? '',
                    'author_id': ownerMid.toString(),
                  },
                );
              } catch (e) {
                SmartDialog.showToast(e.toString());
              }
            },
          ),
      ],
    ),
  );
}

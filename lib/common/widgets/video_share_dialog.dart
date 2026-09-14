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

/// 顯示影片播放頁與 VoiceOver 影片卡共用的分享對話框。
///
/// VoiceOver 的 CustomSemanticsAction 在 iOS 上會於無障礙事件回呼期間執行。
/// 從該回呼立即推 dialog 可能被事件本身吞掉，因此無障礙入口會先跨出
/// 這次事件，再使用目前 App 的 active context 開啟同一個分享對話框。
void showVideoShareDialog({
  required BuildContext context,
  required String bvid,
  int? aid,
  required String title,
  String? cover,
  String? ownerName,
  int? ownerMid,
  String playedTimePos = '',
  bool deferForAccessibility = false,
}) {
  if (bvid.isEmpty) return;

  final videoUrl = '${HttpString.baseUrl}/video/$bvid';
  final isLogin = Accounts.main.isLogin;

  void openDialog() {
    final activeContext = Get.context ?? context;
    if (!activeContext.mounted) return;

    showDialog<void>(
      context: activeContext,
      // VoiceOver 自訂動作由雙擊觸發，避免殘留事件把剛打開的 dialog 關掉。
      barrierDismissible: !deferForAccessibility,
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

  if (deferForAccessibility) {
    Future<void>.delayed(const Duration(milliseconds: 300), openDialog);
  } else {
    openDialog();
  }
}

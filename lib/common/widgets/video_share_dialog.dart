import 'dart:ui' as ui;

import 'package:PiliPlus/http/constants.dart';
import 'package:PiliPlus/pages/dynamics_repost/view.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/id_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/share_utils.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

/// 顯示影片播放頁與 VoiceOver 影片卡共用的分享對話框。
///
/// 影片卡的 bvid 並不保證存在；與開啟影片相同，缺少 bvid 時會使用 aid
/// 換算 BV 號，避免 VoiceOver 分享動作在 `bvid == null` 時無聲退出。
void showVideoShareDialog({
  required BuildContext context,
  String? bvid,
  int? aid,
  required String title,
  String? cover,
  String? ownerName,
  int? ownerMid,
  String playedTimePos = '',
  bool deferForAccessibility = false,
}) {
  var resolvedBvid = bvid;
  if ((resolvedBvid == null || resolvedBvid.isEmpty) && aid != null) {
    resolvedBvid = IdUtils.av2bv(aid);
  }

  if (resolvedBvid == null || resolvedBvid.isEmpty) {
    if (deferForAccessibility) {
      SemanticsService.sendAnnouncement(
        WidgetsBinding.instance.platformDispatcher.views.first,
        '無法取得影片資訊，分享未開啟',
        ui.TextDirection.ltr,
      );
    }
    SmartDialog.showToast('無法取得影片資訊');
    return;
  }

  final videoUrl = '${HttpString.baseUrl}/video/$resolvedBvid';
  final isLogin = Accounts.main.isLogin;

  if (deferForAccessibility) {
    // 這也是診斷標記：若能聽到這句，就代表 CustomSemanticsAction 確實有進入分享 handler。
    SemanticsService.sendAnnouncement(
      WidgetsBinding.instance.platformDispatcher.views.first,
      '正在開啟分享',
      ui.TextDirection.ltr,
    );
  }

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

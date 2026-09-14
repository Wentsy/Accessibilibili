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
/// 換算 BV 號。VoiceOver 自訂動作不直接從 Semantics callback 推路由；
/// 會強制排入下一個 Flutter frame，再由 app 的 root Navigator 開啟同一個分享對話框。
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

  Widget buildShareDialog(BuildContext presentationContext) => SimpleDialog(
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
                  context: presentationContext,
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
                    presentationContext,
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
      );

  if (deferForAccessibility) {
    SemanticsService.sendAnnouncement(
      WidgetsBinding.instance.platformDispatcher.views.first,
      '正在開啟分享',
      ui.TextDirection.ltr,
    );

    // CustomSemanticsAction 不一定會觸發新的 Flutter frame。
    // 主動 scheduleFrame，確保下面的 post-frame callback 一定會執行，
    // 並且已經完全離開 iOS VoiceOver 的 Semantics action callback。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = Get.key.currentState;
      final overlayContext = navigator?.overlay?.context;
      if (navigator == null || overlayContext == null) {
        SmartDialog.showToast('分享介面暫時無法開啟');
        SemanticsService.sendAnnouncement(
          WidgetsBinding.instance.platformDispatcher.views.first,
          '分享介面開啟失敗',
          ui.TextDirection.ltr,
        );
        return;
      }

      navigator.push<void>(
        DialogRoute<void>(
          context: overlayContext,
          barrierDismissible: false,
          builder: (_) => buildShareDialog(overlayContext),
        ),
      );
    });
    WidgetsBinding.instance.scheduleFrame();
    return;
  }

  if (!context.mounted) return;
  showDialog<void>(
    context: context,
    builder: (_) => buildShareDialog(context),
  );
}

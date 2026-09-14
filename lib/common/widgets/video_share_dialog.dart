import 'dart:async';
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

/// 顯示影片播放頁與 VoiceOver 影片卡共用的分享對話框。
///
/// 影片卡的 bvid 並不保證存在；與開啟影片相同，缺少 bvid 時會使用 aid
/// 換算 BV 號。VoiceOver 自訂動作不直接從 Semantics callback 推路由；
/// 只延後到下一個事件迴圈，隨後與播放頁使用相同的 showDialog 路徑。
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

  Widget buildShareDialog(
    BuildContext presentationContext,
    BuildContext dialogContext,
  ) => SimpleDialog(
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
              Navigator.of(dialogContext).pop();
              Utils.copyText(videoUrl);
            },
            trailing: playedTimePos.isNotEmpty
                ? IconButton(
                    tooltip: '精确分享',
                    icon: const Icon(Icons.timer_outlined),
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
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
              Navigator.of(dialogContext).pop();
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
                Navigator.of(dialogContext).pop();
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
                Navigator.of(dialogContext).pop();
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
                Navigator.of(dialogContext).pop();
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

  void reportOpenFailure() {
    SmartDialog.showToast('分享介面暫時無法開啟，請重試');
    if (deferForAccessibility) {
      SemanticsService.sendAnnouncement(
        WidgetsBinding.instance.platformDispatcher.views.first,
        '分享介面開啟失敗，請重試',
        ui.TextDirection.ltr,
      );
    }
  }

  Future<void> openDialog() async {
    if (!context.mounted) {
      reportOpenFailure();
      return;
    }
    try {
      // Keep the originating page's Navigator and inherited theme, exactly as
      // the in-player share button does. Close using the dialog's own context.
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => buildShareDialog(context, dialogContext),
      );
    } catch (error, stackTrace) {
      debugPrint('Unable to open video share dialog: $error\n$stackTrace');
      reportOpenFailure();
    }
  }

  if (deferForAccessibility) {
    // Leave the native semantics callback without waiting for a rendered frame.
    // The dialog itself requests the frame; a post-frame callback must not be
    // the prerequisite for creating it. Let the new route speak its contents.
    Timer.run(() => unawaited(openDialog()));
  } else {
    unawaited(openDialog());
  }
}

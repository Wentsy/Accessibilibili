import 'package:PiliPlus/http/constants.dart';
import 'package:PiliPlus/pages/dynamics_repost/view.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/share_utils.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:flutter/material.dart';

void showVideoShareDialog({
  required BuildContext context,
  required String bvid,
  int? aid,
  required String title,
  String? cover,
  String? ownerName,
  int? ownerMid,
}) {
  if (bvid.isEmpty) return;

  final videoUrl = '${HttpString.baseUrl}/video/$bvid';
  final isLogin = Accounts.main.isLogin;
  final navigator = Navigator.of(context, rootNavigator: true);

  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!navigator.mounted) return;
    showDialog<void>(
      context: navigator.context,
      useRootNavigator: false,
      builder: (dialogContext) => SimpleDialog(
        clipBehavior: Clip.hardEdge,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          ListTile(
            dense: true,
            title: const Text('复制链接', style: TextStyle(fontSize: 14)),
            onTap: () {
              Navigator.of(dialogContext).pop();
              Utils.copyText(videoUrl);
            },
          ),
          ListTile(
            dense: true,
            title: const Text('其它app打开', style: TextStyle(fontSize: 14)),
            onTap: () {
              Navigator.of(dialogContext).pop();
              PageUtils.launchURL(videoUrl);
            },
          ),
          if (PlatformUtils.isMobile)
            ListTile(
              dense: true,
              title: const Text('分享视频', style: TextStyle(fontSize: 14)),
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
              title: const Text('分享至动态', style: TextStyle(fontSize: 14)),
              onTap: () {
                Navigator.of(dialogContext).pop();
                showModalBottomSheet(
                  context: navigator.context,
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
              title: const Text('分享至消息', style: TextStyle(fontSize: 14)),
              onTap: () {
                Navigator.of(dialogContext).pop();
                PageUtils.pmShare(
                  navigator.context,
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
              },
            ),
        ],
      ),
    );
  });
}

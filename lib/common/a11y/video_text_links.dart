import 'package:fixnum/fixnum.dart';
import 'package:get/get.dart';
import 'package:PiliPlus/utils/video_link_targets.dart';
import 'package:PiliPlus/common/a11y/text_link_rotor.dart';
import 'package:PiliPlus/pages/video/controller.dart';
import 'package:PiliPlus/utils/video_timestamps.dart';
import 'package:PiliPlus/utils/url_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

/// Source-order links, without depending on reply oid/type or route arguments.
List<A11yTextLink> videoTextLinks(
  String text,
  VideoDetailController? player, {
  Map<String, String> titles = const {},
  Map<String, Int64> atNameToMid = const {},
}) {
  final links = <A11yTextLink>[];
  final targets = parseVideoLinkTargets(
    text,
    durationMs: player == null
        ? null
        : player.data.timeLength ??
              player.plPlayerController.durationInMilliseconds,
    allowTimes: player != null,
    titles: titles,
  );
  final cid = player?.cid.value;
  final bvid = player?.bvid;
  for (final target in targets) {
    final value = target.destination;
    final time = target.time;
    if (time != null && player != null) {
      links.add(
        A11yTextLink('跳轉至 ${videoTimestampLabel(time)}', () async {
          if (player.isClosed || player.cid.value != cid || player.bvid != bvid)
            return;
          final duration =
              player.data.timeLength ??
              player.plPlayerController.durationInMilliseconds;
          if (duration > 0 && time.inMilliseconds > duration) return;
          try {
            await player.plPlayerController.seekTo(time, isSeek: false);
            SmartDialog.showToast('已跳轉至 ${videoTimestampLabel(time)}');
          } catch (_) {
            SmartDialog.showToast('跳轉失敗，請稍後再試');
          }
        }),
      );
    } else {
      links.add(
        A11yTextLink(target.label, () {
          if (RegExp(r'^(?:BV|av)', caseSensitive: false).hasMatch(value)) {
            UrlUtils.matchUrlPush(value, '');
          } else {
            PageUtils.handleWebview(value);
          }
        }),
      );
    }
  }
  // 留言裡被 @ 的使用者：比照時間軸放進「連結」轉輪，轉到就能直接進他的主頁。
  for (final entry in atNameToMid.entries) {
    final name = entry.key.trim();
    final mid = entry.value;
    if (name.isEmpty || mid <= 0) continue;
    if (!text.contains('@$name')) continue;
    links.add(
      A11yTextLink('@$name 的主頁', () {
        Get.toNamed('/member?mid=$mid');
      }),
    );
  }
  return links;
}

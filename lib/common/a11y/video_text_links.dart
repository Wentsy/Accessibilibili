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
  return links;
}

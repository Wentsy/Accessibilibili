import 'package:PiliPlus/pages/video/controller.dart';
import 'package:PiliPlus/utils/video_timestamps.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';

Future<void> showVideoTimeline(
  BuildContext context,
  VideoDetailController controller,
  List<Duration> times,
) async {
  // Do not seek a different episode if the player changes while the list is open.
  final cid = controller.cid.value;
  final bvid = controller.bvid;
  final selected = await showDialog<Duration>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('時間軸'),
      content: SizedBox(
        width: 360,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: times.length,
          itemBuilder: (context, index) {
            final time = times[index];
            return ListTile(
              title: Text(videoTimestampLabel(time)),
              onTap: () => Navigator.of(dialogContext).pop(time),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('取消'),
        ),
      ],
    ),
  );
  if (selected == null || controller.isClosed) return;
  if (controller.cid.value != cid || controller.bvid != bvid) {
    SmartDialog.showToast('影片已切換，請重新開啟時間軸');
    return;
  }
  final duration =
      controller.data.timeLength ??
      controller.plPlayerController.durationInMilliseconds;
  if (duration > 0 && selected.inMilliseconds > duration) {
    SmartDialog.showToast('時間點超出目前影片長度');
    return;
  }
  try {
    await controller.plPlayerController.seekTo(selected, isSeek: false);
    SmartDialog.showToast('已跳轉至 ${videoTimestampLabel(selected)}');
  } catch (_) {
    SmartDialog.showToast('跳轉失敗，請稍後再試');
  }
}

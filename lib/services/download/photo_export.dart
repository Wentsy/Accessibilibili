import 'dart:io';

import 'package:PiliPlus/models_new/download/bili_download_entry_info.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as path;
import 'package:synchronized/synchronized.dart';

abstract final class PhotoExport {
  static const channel = MethodChannel('accessibilibili/video_export');
  static final status = ValueNotifier<String>('');
  static final _lock = Lock();
  static final _pending = <int>{};

  static void report(String message) {
    status.value = message;
    SmartDialog.showToast(message);
  }

  static Future<bool> requestPermission() async {
    try {
      if (Platform.isIOS &&
          await channel.invokeMethod<bool>('requestPermission') == true) {
        return true;
      }
      report('尚未允許保存到相簿，請在 iPhone 設定中允許此 App 新增照片。');
    } catch (e) {
      report('無法取得相簿權限：${_message(e)}');
    }
    return false;
  }

  static String _message(Object e) =>
      e is PlatformException ? e.message ?? e.code : e.toString();

  static Future<String> prepareMovie({
    required List<String> videos,
    String? audio,
    required int durationMs,
  }) async {
    final output = await channel.invokeMethod<String>('prepareMovie', {
      'videos': videos,
      'audio': audio,
      'durationMs': durationMs,
    });
    if (output == null) throw StateError('沒有產生影片檔案');
    return output;
  }

  static Future<void> save(BiliDownloadEntryInfo entry) async {
    if (!_pending.add(entry.cid)) {
      report('這部影片已在等待保存，請勿重複操作。');
      return;
    }
    try {
      await _lock.synchronized(() async {
        String? output;
        try {
          if (!entry.isCompleted) throw StateError('影片尚未下載完成');
          final dir = path.join(entry.entryDirPath, entry.typeTag!);
          status.value = '正在合成影片：${entry.showTitle}。請保持 App 在前景。';
          output = await prepareMovie(
            videos: [
              path.join(
                dir,
                entry.mediaType == 1
                    ? PathUtils.videoNameType1 : PathUtils.videoNameType2,
              ),
            ],
            audio: entry.mediaType != 1 && entry.hasDashAudio
                ? path.join(dir, PathUtils.audioNameType2) : null,
            durationMs: entry.totalTimeMilli,
          );
          status.value = '正在保存到相簿：${entry.showTitle}';
          await channel.invokeMethod<void>('saveMovie', output);
          report('已保存到相簿：${entry.showTitle}');
        } catch (e) {
          report('保存失敗：${_message(e)}。離線快取仍保留，可從快取頁重試。');
        } finally {
          if (output != null) {
            try { await File(output).delete(); } catch (_) {}
          }
        }
      });
    } finally {
      _pending.remove(entry.cid);
    }
  }
}

/// Persistent, discoverable feedback; no repeated progress announcements that
/// interrupt VoiceOver's continuous reading or the player's audio session.
class PhotoExportStatus extends StatelessWidget {
  const PhotoExportStatus({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
    valueListenable: PhotoExport.status,
    builder: (context, message, _) => message.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Semantics(
              container: true,
              child: Text(message),
            ),
          ),
  );
}

import 'dart:io';

import 'package:PiliPlus/models_new/download/bili_download_entry_info.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as path;
import 'package:synchronized/synchronized.dart';

abstract final class PhotoExport {
  static const channel = MethodChannel('accessibilibili/video_export');
  static const _assetIdsKey = 'photoExportAssetIdsV1';

  static final status = ValueNotifier<String>('');
  static final savedCids = ValueNotifier<Set<int>>(<int>{});
  static final _lock = Lock();
  static final _pending = <int>{};

  static Map<String, String> _assetIds() {
    final value = GStorage.setting.get(_assetIdsKey);
    if (value is! Map) return <String, String>{};
    return <String, String>{
      for (final entry in value.entries)
        if (entry.key != null && entry.value is String)
          entry.key.toString(): entry.value as String,
    };
  }

  static bool hasSavedRecord(int cid) => _assetIds().containsKey('$cid');

  static void _markSaved(int cid) {
    if (savedCids.value.contains(cid)) return;
    savedCids.value = <int>{...savedCids.value, cid};
  }

  static void _unmarkSaved(int cid) {
    if (!savedCids.value.contains(cid)) return;
    final next = <int>{...savedCids.value}..remove(cid);
    savedCids.value = next;
  }

  static Future<void> _recordAsset(int cid, String localIdentifier) async {
    final ids = _assetIds()..['$cid'] = localIdentifier;
    await GStorage.setting.put(_assetIdsKey, ids);
    _markSaved(cid);
  }

  static Future<void> _forgetAsset(int cid) async {
    final ids = _assetIds();
    if (ids.remove('$cid') != null) {
      await GStorage.setting.put(_assetIdsKey, ids);
    }
    _unmarkSaved(cid);
  }

  /// Re-check the actual Photos asset instead of trusting a permanent local
  /// flag. If the user deletes the video in Photos, the saved state is cleared.
  static Future<bool> refreshSavedState(int cid) async {
    final localIdentifier = _assetIds()['$cid'];
    if (localIdentifier == null || localIdentifier.isEmpty) {
      _unmarkSaved(cid);
      return false;
    }
    try {
      final exists =
          await channel.invokeMethod<bool>('assetExists', localIdentifier) ==
          true;
      if (exists) {
        _markSaved(cid);
        return true;
      }
      await _forgetAsset(cid);
      return false;
    } on PlatformException catch (e) {
      // If Photos access was revoked, iOS cannot verify deletion. Preserve the
      // last known state rather than incorrectly claiming the asset vanished.
      if (e.code == 'photos_permission') {
        _markSaved(cid);
        return true;
      }
      return hasSavedRecord(cid);
    } catch (_) {
      return hasSavedRecord(cid);
    }
  }

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
      report('尚未允許照片存取，請在 iPhone 設定中允許此 App 存取照片，以便保存影片並確認影片是否仍在相簿中。');
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
    if (await refreshSavedState(entry.cid)) {
      report('已保存到相簿：${entry.showTitle}');
      return;
    }
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
                    ? PathUtils.videoNameType1
                    : PathUtils.videoNameType2,
              ),
            ],
            audio: entry.mediaType != 1 && entry.hasDashAudio
                ? path.join(dir, PathUtils.audioNameType2)
                : null,
            durationMs: entry.totalTimeMilli,
          );
          status.value = '正在保存到相簿：${entry.showTitle}';
          final localIdentifier =
              await channel.invokeMethod<String>('saveMovie', output);
          if (localIdentifier == null || localIdentifier.isEmpty) {
            throw StateError('照片圖庫沒有回傳影片識別碼');
          }
          await _recordAsset(entry.cid, localIdentifier);
          report('已保存到相簿：${entry.showTitle}');
        } catch (e) {
          report('保存失敗：${_message(e)}。離線快取仍保留，可從快取頁重試。');
        } finally {
          if (output != null) {
            try {
              await File(output).delete();
            } catch (_) {}
          }
        }
      });
    } finally {
      _pending.remove(entry.cid);
    }
  }
}

/// The video action reflects the asset that currently exists in Photos. It
/// re-checks on page/video changes and whenever the app returns from Photos, so
/// deleting the exported movie restores the original save action.
class PhotoExportButton extends StatefulWidget {
  const PhotoExportButton({
    super.key,
    required this.cid,
    required this.onPressed,
  });

  final int cid;
  final Future<void> Function() onPressed;

  @override
  State<PhotoExportButton> createState() => _PhotoExportButtonState();
}

class _PhotoExportButtonState extends State<PhotoExportButton>
    with WidgetsBindingObserver {
  bool _saved = false;
  int _refreshGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PhotoExport.savedCids.addListener(_onSavedCidsChanged);
    _saved = PhotoExport.hasSavedRecord(widget.cid);
    _refresh();
  }

  @override
  void didUpdateWidget(PhotoExportButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cid != widget.cid) {
      _saved = PhotoExport.hasSavedRecord(widget.cid);
      _refresh();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  void _onSavedCidsChanged() {
    if (!mounted) return;
    final saved = PhotoExport.savedCids.value.contains(widget.cid);
    if (saved != _saved) setState(() => _saved = saved);
  }

  Future<void> _refresh() async {
    final cid = widget.cid;
    final generation = ++_refreshGeneration;
    final saved = await PhotoExport.refreshSavedState(cid);
    if (!mounted || generation != _refreshGeneration || cid != widget.cid) {
      return;
    }
    if (saved != _saved) setState(() => _saved = saved);
  }

  Future<void> _save() async {
    await widget.onPressed();
    await _refresh();
  }

  @override
  void dispose() {
    ++_refreshGeneration;
    PhotoExport.savedCids.removeListener(_onSavedCidsChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextButton.icon(
    icon: Icon(
      _saved ? Icons.check_rounded : Icons.photo_library_outlined,
    ),
    label: Text(_saved ? '已保存到相簿' : '保存到相簿'),
    onPressed: _saved ? null : _save,
  );
}

/// Retained for compatibility with older routes. The main video page now uses
/// [PhotoExportButton] as the single persistent state indicator.
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

import 'dart:async';
import 'dart:convert' show jsonDecode, jsonEncode;
import 'dart:io' show Directory, File, Platform;

import 'package:PiliPlus/grpc/dm.dart';
import 'package:PiliPlus/http/download.dart';
import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/video/video_quality.dart';
import 'package:PiliPlus/models_new/download/bili_download_entry_info.dart';
import 'package:PiliPlus/models_new/download/bili_download_media_file_info.dart';
import 'package:PiliPlus/models_new/pgc/pgc_info_model/episode.dart' as pgc;
import 'package:PiliPlus/models_new/pgc/pgc_info_model/result.dart';
import 'package:PiliPlus/models_new/video/video_detail/data.dart';
import 'package:PiliPlus/models_new/video/video_detail/episode.dart' as ugc;
import 'package:PiliPlus/models_new/video/video_detail/page.dart';
import 'package:PiliPlus/pages/danmaku/controller.dart';
import 'package:PiliPlus/services/download/download_manager.dart';
import 'package:PiliPlus/services/download/photo_export.dart';
import 'package:PiliPlus/utils/cache_manager.dart';
import 'package:PiliPlus/utils/extension/file_ext.dart';
import 'package:PiliPlus/utils/extension/string_ext.dart';
import 'package:PiliPlus/utils/id_utils.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as path;
import 'package:synchronized/synchronized.dart';

// ref https://github.com/10miaomiao/bilimiao2/blob/master/bilimiao-download/src/main/java/cn/a10miaomiao/bilimiao/download/DownloadService.kt

class DownloadService extends GetxService {
  static const _entryFile = 'entry.json';
  static const _indexFile = 'index.json';

  final _lock = Lock();
  final _creationLock = Lock();
  final _entryWriteLock = Lock();
  int _generation = 0;

  final flagNotifier = SetNotifier();
  final waitDownloadQueue = RxList<BiliDownloadEntryInfo>();
  final downloadList = <BiliDownloadEntryInfo>[];

  int? _curCid;
  int? get curCid => _curCid;
  final curDownload = Rxn<BiliDownloadEntryInfo>();
  void _updateCurStatus(DownloadStatus status) {
    if (curDownload.value != null) {
      curDownload
        ..value!.status = status
        ..refresh();
      final entry = curDownload.value!;
      if (entry.saveToPhotos && status.isDownloading) {
        PhotoExport.status.value = '${status.message}：${entry.showTitle}';
      }
      if (entry.saveToPhotos && !status.isDownloading && status != DownloadStatus.completed) {
        PhotoExport.report('${entry.showTitle}：${status.message}，可再次按保存到相簿重試。');
      }
    }
  }

  DownloadManager? _downloadManager;
  DownloadManager? _audioDownloadManager;

  late Future<void> waitForInitialization;

  @override
  void onInit() {
    super.onInit();
    initDownloadList();
  }

  void initDownloadList() {
    waitForInitialization = _readDownloadList();
  }

  Future<void> _readDownloadList() async {
    downloadList.clear();
    final downloadDir = Directory(await _getDownloadPath());
    await for (final dir in downloadDir.list()) {
      if (dir is Directory) {
        downloadList.addAll(await _readDownloadDirectory(dir));
      }
    }
    downloadList.sort((a, b) => b.timeUpdateStamp.compareTo(a.timeUpdateStamp));
  }

  @pragma('vm:notify-debugger-on-exception')
  Future<List<BiliDownloadEntryInfo>> _readDownloadDirectory(
    Directory pageDir,
  ) async {
    final result = <BiliDownloadEntryInfo>[];

    if (!pageDir.existsSync()) {
      return result;
    }

    await for (final entryDir in pageDir.list()) {
      if (entryDir is Directory) {
        final entryFile = File(path.join(entryDir.path, _entryFile));
        if (entryFile.existsSync()) {
          try {
            final entryJson = await entryFile.readAsString();
            final entry = BiliDownloadEntryInfo.fromJson(jsonDecode(entryJson))
              ..pageDirPath = pageDir.path
              ..entryDirPath = entryDir.path;
            if (entry.isCompleted) {
              result.add(entry);
            } else {
              waitDownloadQueue.add(entry..status = DownloadStatus.wait);
            }
          } catch (_) {}
        }
      }
    }

    return result;
  }

  Future<BiliDownloadEntryInfo> downloadVideo(
    Part page,
    VideoDetailData? videoDetail,
    ugc.EpisodeItem? videoArc,
    VideoQuality videoQuality, {
    bool saveToPhotos = false,
  }) async {
    final cid = page.cid!;
    await waitForInitialization;
    for (final existing in downloadList.followedBy(waitDownloadQueue)) {
      if (existing.cid == cid) {
        if (saveToPhotos) await requestPhotoExport(existing);
        return existing;
      }
    }
    final pageData = PageInfo(
      cid: cid,
      page: page.page!,
      from: page.from,
      part: page.part,
      vid: page.vid,
      hasAlias: false,
      tid: 0,
      width: 0,
      height: 0,
      rotate: 0,
      downloadTitle: '视频已缓存完成',
      downloadSubtitle: videoDetail?.title ?? videoArc!.title,
    );
    final currentTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final entry = BiliDownloadEntryInfo(
      mediaType: 2,
      hasDashAudio: false,
      isCompleted: false,
      saveToPhotos: saveToPhotos,
      totalBytes: 0,
      downloadedBytes: 0,
      title: videoDetail?.title ?? videoArc!.title!,
      typeTag: videoQuality.code.toString(),
      cover: (videoDetail?.pic ?? videoArc!.cover!).http2https,
      preferedVideoQuality: videoQuality.code,
      qualityPithyDescription: videoQuality.desc,
      guessedTotalBytes: 0,
      totalTimeMilli: (page.duration ?? 0) * 1000,
      danmakuCount:
          videoDetail?.stat?.danmaku ?? videoArc?.arc?.stat?.danmaku ?? 0,
      timeUpdateStamp: currentTime,
      timeCreateStamp: currentTime,
      canPlayInAdvance: true,
      interruptTransformTempFile: false,
      avid: videoDetail?.aid ?? videoArc!.aid!,
      spid: 0,
      seasonId: null,
      ep: null,
      source: null,
      bvid: videoDetail?.bvid ?? videoArc!.bvid!,
      ownerId: videoDetail?.owner?.mid ?? videoArc?.arc?.author?.mid,
      ownerName: videoDetail?.owner?.name ?? videoArc?.arc?.author?.name,
      pageData: pageData,
    );
    final created = await _createDownload(entry);
    if (saveToPhotos && !created.isCompleted) {
      PhotoExport.report('正在下載：${created.showTitle}。完成後會保存到相簿，請保持 App 在前景。');
    }
    return created;
  }

  Future<BiliDownloadEntryInfo> downloadBangumi(
    int index,
    PgcInfoModel pgcItem,
    pgc.EpisodeItem episode,
    VideoQuality quality, {
    bool saveToPhotos = false,
  }) async {
    final cid = episode.cid!;
    await waitForInitialization;
    for (final existing in downloadList.followedBy(waitDownloadQueue)) {
      if (existing.cid == cid) {
        if (saveToPhotos) await requestPhotoExport(existing);
        return existing;
      }
    }
    final currentTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final source = SourceInfo(
      avId: episode.aid!,
      cid: cid,
    );
    final ep = EpInfo(
      avId: source.avId,
      page: index,
      danmaku: source.cid,
      cover: episode.cover!,
      episodeId: episode.id!,
      index: episode.title!,
      indexTitle: episode.longTitle ?? '',
      showTitle: episode.showTitle,
      from: episode.from ?? 'bangumi',
      seasonType: pgcItem.type ?? (episode.from == 'pugv' ? -1 : 0),
      width: 0,
      height: 0,
      rotate: 0,
      link: episode.link ?? '',
      bvid: episode.bvid ?? IdUtils.av2bv(source.avId),
      sortIndex: index,
    );
    final entry = BiliDownloadEntryInfo(
      mediaType: 2,
      hasDashAudio: false,
      isCompleted: false,
      saveToPhotos: saveToPhotos,
      totalBytes: 0,
      downloadedBytes: 0,
      title: pgcItem.seasonTitle ?? pgcItem.title ?? '',
      typeTag: quality.code.toString(),
      cover: episode.cover!,
      preferedVideoQuality: quality.code,
      qualityPithyDescription: quality.desc,
      guessedTotalBytes: 0,
      totalTimeMilli:
          (episode.duration ?? 0) *
          (episode.from == 'pugv' ? 1000 : 1), // pgc millisec,, pugv sec
      danmakuCount: pgcItem.stat?.danmaku ?? 0,
      timeUpdateStamp: currentTime,
      timeCreateStamp: currentTime,
      canPlayInAdvance: true,
      interruptTransformTempFile: false,
      spid: 0,
      seasonId: pgcItem.seasonId!.toString(),
      bvid: episode.bvid ?? IdUtils.av2bv(source.avId),
      avid: source.avId,
      ep: ep,
      source: source,
      ownerId: pgcItem.upInfo?.mid,
      ownerName: pgcItem.upInfo?.uname,
      pageData: null,
    );
    final created = await _createDownload(entry);
    if (saveToPhotos && !created.isCompleted) {
      PhotoExport.report('正在下載：${created.showTitle}。完成後會保存到相簿，請保持 App 在前景。');
    }
    return created;
  }

  Future<BiliDownloadEntryInfo> _createDownload(BiliDownloadEntryInfo entry) =>
      _creationLock.synchronized(() async {
        for (final existing in downloadList.followedBy(waitDownloadQueue)) {
          if (existing.cid == entry.cid) {
            if (entry.saveToPhotos) await requestPhotoExport(existing);
            return existing;
          }
        }
        final entryDir = await _getDownloadEntryDir(entry);
        final entryJsonFile = File(path.join(entryDir.path, _entryFile));
        await entryJsonFile.writeAsString(jsonEncode(entry.toJson()));
        entry
          ..pageDirPath = entryDir.parent.path
          ..entryDirPath = entryDir.path
          ..status = DownloadStatus.wait;
        waitDownloadQueue.add(entry);
        if (curDownload.value?.status.isDownloading != true) {
          startDownload(entry);
        }
        return entry;
      });

  Future<Directory> _getDownloadEntryDir(BiliDownloadEntryInfo entry) async {
    late final String dirName;
    late final String pageDirName;
    if (entry.ep case final ep?) {
      dirName = 's_${entry.seasonId}';
      pageDirName = ep.episodeId.toString();
    } else if (entry.pageData case final page?) {
      dirName = entry.avid.toString();
      pageDirName = 'c_${page.cid}';
    }
    final pageDir = Directory(
      path.join(await _getDownloadPath(), dirName, pageDirName),
    );
    if (!pageDir.existsSync()) {
      await pageDir.create(recursive: true);
    }
    return pageDir;
  }

  static Future<String> _getDownloadPath() async {
    final dir = Directory(downloadPath);
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  Future<void> startDownload(BiliDownloadEntryInfo entry) {
    return _lock.synchronized(() async {
      if (entry.isCompleted) return;
      ++_generation;
      await _downloadManager?.cancel(isDelete: false);
      await _audioDownloadManager?.cancel(isDelete: false);
      _downloadManager = null;
      _audioDownloadManager = null;
      if (curDownload.value case final curEntry?) {
        if (curEntry.status.isDownloading) {
          curEntry.status = DownloadStatus.pause;
        }
      }

      _curCid = entry.cid;
      curDownload.value = entry;
      waitDownloadQueue.refresh();
      await _startDownload(entry);
    });
  }

  Future<bool> downloadDanmaku({
    required BiliDownloadEntryInfo entry,
    bool isUpdate = false,
  }) async {
    final cid = entry.pageData?.cid ?? entry.source?.cid;
    if (cid == null) {
      return false;
    }
    final danmakuFile = File(
      path.join(entry.entryDirPath, PathUtils.danmakuName),
    );
    if (isUpdate || !danmakuFile.existsSync()) {
      try {
        if (!isUpdate) {
          _updateCurStatus(DownloadStatus.getDanmaku);
        }
        final seg = (entry.totalTimeMilli / PlDanmakuController.segmentLength)
            .ceil();

        final res = await Future.wait([
          for (var i = 1; i <= seg; i++)
            DmGrpc.dmSegMobile(cid: cid, segmentIndex: i),
        ]);

        final danmaku = res.removeAt(0).data;
        for (final i in res) {
          if (i case Success(:final response)) {
            danmaku.elems.addAll(response.elems);
          }
        }
        res.clear();
        await danmakuFile.writeAsBytes(danmaku.writeToBuffer());

        return true;
      } catch (e) {
        if (!isUpdate) {
          _updateCurStatus(DownloadStatus.failDanmaku);
        }
        if (kDebugMode) SmartDialog.showToast(e.toString());
        return false;
      }
    }
    return true;
  }

  Future<bool> _downloadCover({
    required BiliDownloadEntryInfo entry,
  }) async {
    try {
      final filePath = path.join(entry.entryDirPath, PathUtils.coverName);
      if (File(filePath).existsSync()) {
        return true;
      }
      final file = (await CacheManager.manager.getFileFromCache(
        entry.cover,
      ))?.file;
      if (file != null) {
        await file.copy(filePath);
      } else {
        await Request.dio.download(entry.cover, filePath);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _startDownload(BiliDownloadEntryInfo entry) async {
    final generation = _generation;
    try {
      if (!entry.saveToPhotos && !await downloadDanmaku(entry: entry)) {
        return;
      }

      if (generation != _generation) return;
      _updateCurStatus(DownloadStatus.getPlayUrl);

      final mediaFileInfo = await DownloadHttp.getVideoUrl(
        entry: entry,
        ep: entry.ep,
        source: entry.source,
        pageData: entry.pageData,
      );

      if (generation != _generation) return;
      final videoDir = Directory(path.join(entry.entryDirPath, entry.typeTag));
      if (!videoDir.existsSync()) {
        await videoDir.create(recursive: true);
      }

      final mediaJsonFile = File(path.join(videoDir.path, _indexFile));
      await Future.wait([
        mediaJsonFile.writeAsString(jsonEncode(mediaFileInfo.toJson())),
        _downloadCover(entry: entry),
      ]);

      if (generation != _generation || curDownload.value?.cid != entry.cid) {
        return;
      }

      switch (mediaFileInfo) {
        case Type1 mediaFileInfo:
          if (mediaFileInfo.segmentList.length > 1) {
            unawaited(_downloadSegments(entry, mediaFileInfo, videoDir, generation));
            return;
          }
          final first = mediaFileInfo.segmentList.first;
          _downloadManager = DownloadManager(
            url: first.url,
            headers: mediaFileInfo.httpHeader,
            path: path.join(videoDir.path, PathUtils.videoNameType1),
            onReceiveProgress: (received, total) {
              if (generation == _generation) _onReceive(received, total);
            },
            onDone: ([error]) {
              if (generation == _generation) _onDone(error);
            },
          );
          break;
        case Type2 mediaFileInfo:
          _downloadManager = DownloadManager(
            url: mediaFileInfo.video.first.baseUrl,
            headers: mediaFileInfo.httpHeader,
            path: path.join(videoDir.path, PathUtils.videoNameType2),
            onReceiveProgress: (received, total) {
              if (generation == _generation) _onReceive(received, total);
            },
            onDone: ([error]) {
              if (generation == _generation) _onDone(error);
            },
          );
          final audio = mediaFileInfo.audio;
          if (audio != null && audio.isNotEmpty) {
            _audioDownloadManager = DownloadManager(
              url: audio.first.baseUrl,
              headers: mediaFileInfo.httpHeader,
              path: path.join(videoDir.path, PathUtils.audioNameType2),
              onReceiveProgress: null,
              onDone: ([error]) {
                if (generation == _generation) _onAudioDone(error);
              },
            );
          }
          late final first = mediaFileInfo.video.first;
          entry.pageData
            ?..width = first.width
            ..height = first.height;
          entry.ep
            ?..width = first.width
            ..height = first.height;
          _updateBiliDownloadEntryJson(entry);
          break;
        default:
          break;
      }
    } catch (e) {
      if (generation != _generation) return;
      _updateCurStatus(DownloadStatus.failPlayUrl);
      if (entry.saveToPhotos) PhotoExport.report('無法下載影片：$e');
      if (kDebugMode) {
        debugPrint('get download url error: $e');
      }
    }
  }

  Future<void> _downloadSegments(BiliDownloadEntryInfo entry, Type1 media,
      Directory dir, int generation) async {
    String? output;
    try {
      if (!Platform.isIOS) {
        throw UnsupportedError('此平台尚不支援分段影片合成');
      }
      final videos = <String>[];
      final total = media.segmentList.fold<int>(0, (sum, s) => sum + s.bytes);
      int finished = 0;
      for (int i = 0; i < media.segmentList.length; i++) {
        if (generation != _generation) return;
        final segment = media.segmentList[i];
        final file = path.join(dir.path, 'segment_$i.mp4');
        videos.add(file);
        final manager = DownloadManager(
          url: segment.url,
          path: file,
          headers: media.httpHeader,
          onReceiveProgress: (received, _) {
            if (generation != _generation) return;
            entry.totalBytes = total;
            _onReceive(finished + received, total);
          },
          onDone: ([error]) {},
        );
        _downloadManager = manager;
        await manager.task;
        if (generation != _generation) return;
        if (manager.status != DownloadStatus.completed) {
          throw StateError('第 ${i + 1} 段下載失敗');
        }
        finished += await File(file).length();
      }
      _updateCurStatus(DownloadStatus.merging);
      output = await PhotoExport.prepareMovie(
        videos: videos,
        durationMs: media.segmentList.fold<int>(0, (sum, s) => sum + s.duration),
      );
      if (generation != _generation) return;
      await File(output).copy(path.join(dir.path, PathUtils.videoNameType1));
      if (generation != _generation) return;
      await _completeDownload();
      for (final file in videos) {
        try { await File(file).delete(); } catch (_) {}
      }
    } catch (e) {
      if (generation == _generation) {
        _updateCurStatus(DownloadStatus.failDownload);
        PhotoExport.report('分段影片下載或合成失敗：$e');
      }
    } finally {
      if (output != null) {
        try { await File(output).delete(); } catch (_) {}
      }
    }
  }

  Future<void> _updateBiliDownloadEntryJson(BiliDownloadEntryInfo entry) =>
      _entryWriteLock.synchronized(() async {
        final entryJsonFile = File(path.join(entry.entryDirPath, _entryFile));
        await entryJsonFile.writeAsString(jsonEncode(entry.toJson()));
      });

  void _onReceive(int progress, int total) {
    if (curDownload.value case final entry?) {
      if (total > 0 && entry.totalBytes != total) {
        _updateBiliDownloadEntryJson(entry..totalBytes = total);
      }
      entry
        ..downloadedBytes = progress
        ..status = DownloadStatus.downloading;
      curDownload.refresh();
      if (entry.saveToPhotos) {
        final percent = total > 0 ? '${(progress * 100 / total).floor()}%' : '';
        PhotoExport.status.value = '正在下載 $percent：${entry.showTitle}。完成後會保存到相簿。';
      }
    }
  }

  void _onDone([Object? error]) {
    if (error != null) {
      _updateCurStatus(_downloadManager?.status ?? DownloadStatus.pause);
      return;
    }

    final status = switch (_audioDownloadManager?.status) {
      DownloadStatus.downloading => DownloadStatus.audioDownloading,
      DownloadStatus.failDownload => DownloadStatus.failDownloadAudio,
      _ => _downloadManager?.status ?? DownloadStatus.pause,
    };
    _updateCurStatus(status);

    if (curDownload.value case final curEntryInfo?) {
      curEntryInfo.downloadedBytes = curEntryInfo.totalBytes;
      if (status == DownloadStatus.completed) {
        _completeDownload();
      } else {
        _updateBiliDownloadEntryJson(curEntryInfo);
      }
    }
  }

  void _onAudioDone([Object? error]) {
    if (_downloadManager?.status == DownloadStatus.completed) {
      if (error == null) {
        _completeDownload();
      } else {
        final status = _audioDownloadManager?.status ?? DownloadStatus.pause;
        _updateCurStatus(
          status == DownloadStatus.failDownload
              ? DownloadStatus.failDownloadAudio
              : status,
        );
      }
    }
  }

  Future<void> _completeDownload() async {
    final entry = curDownload.value;
    if (entry == null || entry.isCompleted) {
      return;
    }
    final shouldSave = entry.saveToPhotos;
    entry
      ..saveToPhotos = false
      ..downloadedBytes = entry.totalBytes
      ..isCompleted = true;
    // Claim the export synchronously before publishing completed state to other
    // routes, so a repeated tap cannot race the automatic completion callback.
    final photoExportTask = shouldSave ? PhotoExport.save(entry) : null;
    await _updateBiliDownloadEntryJson(entry);
    waitDownloadQueue.remove(entry);
    downloadList.insert(0, entry);
    flagNotifier.refresh();
    if (identical(curDownload.value, entry)) {
      _curCid = null;
      curDownload.value = null;
      _downloadManager = null;
      _audioDownloadManager = null;
      nextDownload();
    }
    if (photoExportTask != null) await photoExportTask;
  }

  Future<void> requestPhotoExport(BiliDownloadEntryInfo entry) async {
    if (entry.isCompleted) {
      await PhotoExport.save(entry);
    } else {
      entry.saveToPhotos = true;
      await _updateBiliDownloadEntryJson(entry);
      if (entry.isCompleted) return;
      PhotoExport.report('已加入保存佇列：${entry.showTitle}。下載完成後會保存到相簿，請保持 App 在前景。');
      if (curDownload.value?.status.isDownloading != true) {
        await startDownload(entry);
      }
    }
  }

  void nextDownload() {
    if (waitDownloadQueue.isNotEmpty) {
      startDownload(waitDownloadQueue.first);
    }
  }

  Future<void> deleteDownload({
    required BiliDownloadEntryInfo entry,
    bool removeList = false,
    bool removeQueue = false,
    bool refresh = true,
    bool downloadNext = true,
  }) async {
    if (removeList) {
      downloadList.remove(entry);
    }
    if (removeQueue) {
      waitDownloadQueue.remove(entry);
    }
    if (curDownload.value?.cid == entry.cid) {
      await cancelDownload(
        isDelete: true,
        downloadNext: downloadNext,
      );
    }
    final downloadDir = Directory(entry.pageDirPath);
    if (downloadDir.existsSync()) {
      if (!await downloadDir.lengthGte(2)) {
        await downloadDir.tryDel(recursive: true);
      } else {
        final entryDir = Directory(entry.entryDirPath);
        if (entryDir.existsSync()) {
          await entryDir.tryDel(recursive: true);
        }
      }
    }
    if (refresh) {
      flagNotifier.refresh();
    }
  }

  Future<void> deletePage({
    required String pageDirPath,
    bool refresh = true,
  }) async {
    await Directory(pageDirPath).tryDel(recursive: true);
    downloadList.removeWhere((e) => e.pageDirPath == pageDirPath);
    if (refresh) {
      flagNotifier.refresh();
    }
  }

  Future<void> cancelDownload({
    required bool isDelete,
    bool downloadNext = true,
  }) async {
    ++_generation;
    await _downloadManager?.cancel(isDelete: isDelete);
    await _audioDownloadManager?.cancel(isDelete: isDelete);
    _downloadManager = null;
    _audioDownloadManager = null;
    if (!isDelete) {
      final entry = curDownload.value;
      if (entry != null) {
        await _updateBiliDownloadEntryJson(entry);
      }
    }
    if (isDelete) {
      _curCid = null;
      curDownload.value = null;
    } else {
      _updateCurStatus(DownloadStatus.pause);
    }
    if (downloadNext) {
      nextDownload();
    }
  }
}

typedef SetNotifier = Set<VoidCallback>;

extension SetNotifierExt on SetNotifier {
  void refresh() {
    for (final i in this) {
      i();
    }
  }
}

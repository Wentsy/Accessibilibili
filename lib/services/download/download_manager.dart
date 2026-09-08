import 'dart:async';
import 'dart:io';

import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/models_new/download/bili_download_entry_info.dart';
import 'package:PiliPlus/utils/extension/string_ext.dart';
import 'package:dio/dio.dart';

class DownloadManager {
  final String url;
  final String path;
  final Map<String, String> headers;
  final void Function(int, int)? onReceiveProgress;
  final void Function([Object? error]) onDone;
  final Dio? client;

  DownloadStatus _status = DownloadStatus.downloading;
  DownloadStatus get status => _status;
  final _cancelToken = CancelToken();
  late Future<void> task;

  DownloadManager({
    required this.url,
    required this.path,
    this.headers = const {},
    this.client,
    this.onReceiveProgress,
    required this.onDone,
  }) {
    task = _start();
  }

  Future<void> _start() async {
    IOSink? sink;
    try {
      final file = File(path);
      int received = file.existsSync() ? await file.length() : 0;
      final response = await (client ?? Request.http11Dio).get<ResponseBody>(
        url.http2https,
        options: Options(
          headers: {...headers, if (received > 0) 'range': 'bytes=$received-'},
          responseType: ResponseType.stream,
          validateStatus: (status) => status == 200 || status == 206 || status == 416,
        ),
        cancelToken: _cancelToken,
      );
      final body = response.data!;
      final range = response.headers.value('content-range');
      if (response.statusCode == 416) {
        await body.stream.listen(null).cancel();
        final match = RegExp(r'^bytes \*/(\d+)$').firstMatch(range ?? '');
        if (received > 0 && match != null && int.parse(match[1]!) == received) {
          if (_cancelToken.isCancelled) throw StateError('下載已暫停');
          onReceiveProgress?.call(received, received);
          _status = DownloadStatus.completed;
          onDone();
          return;
        }
        // A stale, oversized cache is not a completed file. Start clean on retry.
        if (file.existsSync()) await file.delete();
        throw StateError('下載範圍失效，請重試');
      }
      int total;
      if (response.statusCode == 206) {
        final match = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(range ?? '');
        if (match == null || int.parse(match[1]!) != received ||
            int.parse(match[2]!) + 1 != int.parse(match[3]!)) {
          await body.stream.listen(null).cancel();
          throw StateError('伺服器回傳的續傳範圍不完整');
        }
        total = int.parse(match[3]!);
      } else {
        // Some CDNs ignore Range and send the whole file. Never append that to
        // the partial file, which creates corruption and false completion.
        received = 0;
        total = body.contentLength;
      }
      if (_cancelToken.isCancelled) {
        await body.stream.listen(null).cancel();
        throw StateError('下載已暫停');
      }
      await file.parent.create(recursive: true);
      sink = file.openWrite(mode: received == 0 ? FileMode.writeOnly : FileMode.writeOnlyAppend);
      onReceiveProgress?.call(received, total > 0 ? total : 0);
      int? last;
      await for (final chunk in body.stream) {
        if (_cancelToken.isCancelled) throw StateError('下載已暫停');
        sink.add(chunk);
        received += chunk.length;
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        if (last != now) {
          last = now;
          onReceiveProgress?.call(received, total > 0 ? total : received);
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (_cancelToken.isCancelled) throw StateError('下載已暫停');
      if (received == 0 || (total > 0 && received != total)) {
        throw StateError('下載檔案不完整，請重試續傳');
      }
      onReceiveProgress?.call(received, received);
      _status = DownloadStatus.completed;
      onDone();
    } catch (e) {
      if (sink != null) {
        try { await sink.close(); } catch (_) {}
      }
      if (_status == DownloadStatus.downloading) {
        _status = DownloadStatus.failDownload;
      }
      onDone(e);
    }
  }

  Future<void> cancel({required bool isDelete}) {
    if (_status == DownloadStatus.downloading) _status = DownloadStatus.pause;
    if (!_cancelToken.isCancelled) _cancelToken.cancel();
    return task;
  }
}

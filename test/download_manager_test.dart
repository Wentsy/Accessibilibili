import 'dart:io';
import 'dart:typed_data';

import 'package:PiliPlus/models_new/download/bili_download_entry_info.dart';
import 'package:PiliPlus/services/download/download_manager.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class ResponseAdapter implements HttpClientAdapter {
  ResponseAdapter(this.respond);
  final ResponseBody Function(RequestOptions) respond;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async => respond(options);

  @override
  void close({bool force = false}) {}
}

void main() {
  late Directory directory;
  late File file;
  late Dio client;
  Object? error;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('video-download-test-');
    file = File('${directory.path}/video.m4s');
    client = Dio();
    error = null;
  });
  tearDown(() async {
    client.close(force: true);
    await directory.delete(recursive: true);
  });

  Future<DownloadManager> download(ResponseBody Function(RequestOptions) response) async {
    client.httpClientAdapter = ResponseAdapter(response);
    final manager = DownloadManager(
      url: 'https://video.example/test',
      path: file.path,
      client: client,
      headers: const {'referer': 'https://www.bilibili.com/'},
      onDone: ([e]) => error = e,
    );
    await manager.task;
    return manager;
  }

  test('a CDN ignoring Range replaces the partial file, never appends', () async {
    await file.writeAsBytes([1, 2]);
    final manager = await download((options) {
      expect(options.headers['range'], 'bytes=2-');
      expect(options.headers['referer'], 'https://www.bilibili.com/');
      return ResponseBody.fromBytes([1, 2, 3, 4], 200, headers: {
        'content-length': ['4'],
      });
    });
    expect(manager.status, DownloadStatus.completed);
    expect(error, isNull);
    expect(await file.readAsBytes(), [1, 2, 3, 4]);
  });

  test('valid partial response resumes from the exact byte offset', () async {
    await file.writeAsBytes([1, 2]);
    final manager = await download((_) => ResponseBody.fromBytes([3, 4], 206, headers: {
      'content-length': ['2'], 'content-range': ['bytes 2-3/4'],
    }));
    expect(manager.status, DownloadStatus.completed);
    expect(await file.readAsBytes(), [1, 2, 3, 4]);
  });

  test('wrong partial offset cannot corrupt or complete the cache', () async {
    await file.writeAsBytes([1, 2]);
    final manager = await download((_) => ResponseBody.fromBytes([2, 3, 4], 206, headers: {
      'content-length': ['3'], 'content-range': ['bytes 1-3/4'],
    }));
    expect(manager.status, DownloadStatus.failDownload);
    expect(error, isNotNull);
    expect(await file.readAsBytes(), [1, 2]);
  });

  test('truncated successful HTTP response is not a complete video', () async {
    final manager = await download((_) => ResponseBody.fromBytes([1, 2], 200, headers: {
      'content-length': ['4'],
    }));
    expect(manager.status, DownloadStatus.failDownload);
    expect(error, isNotNull);
  });

  test('416 is complete only when local and remote file sizes match', () async {
    await file.writeAsBytes([1, 2, 3, 4]);
    final manager = await download((_) => ResponseBody.fromBytes([], 416, headers: {
      'content-range': ['bytes */4'],
    }));
    expect(manager.status, DownloadStatus.completed);
    expect(error, isNull);
    expect(await file.readAsBytes(), [1, 2, 3, 4]);
  });

  test('416 with a stale oversized file fails and permits a clean retry', () async {
    await file.writeAsBytes([1, 2, 3, 4, 5]);
    final manager = await download((_) => ResponseBody.fromBytes([], 416, headers: {
      'content-range': ['bytes */4'],
    }));
    expect(manager.status, DownloadStatus.failDownload);
    expect(error, isNotNull);
    expect(file.existsSync(), isFalse);
  });
}

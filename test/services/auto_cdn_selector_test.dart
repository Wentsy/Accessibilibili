// ignore_for_file: avoid_relative_lib_imports, avoid_print
// Standalone regression test: dart run test/services/auto_cdn_selector_test.dart
import 'dart:async';
import 'dart:io';

import '../../lib/services/auto_cdn_selector.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final base = 'http://127.0.0.1:${server.port}';
  var requests = 0;
  var validHeaders = true;
  var active = 0;
  var maxActive = 0;
  final handlers = <Future<void>>[];
  final subscription = server.listen((request) {
    handlers.add(() async {
      requests++;
      active++;
      if (active > maxActive) maxActive = active;
      try {
        validHeaders =
            validHeaders &&
            request.headers.value('range') == 'bytes=0-65535' &&
            request.headers.value('referer') == 'https://www.bilibili.com';
        final path = request.uri.path;
        if (path == '/slow') {
          await Future<void>.delayed(const Duration(milliseconds: 450));
        }
        if (path == '/forbidden') {
          request.response.statusCode = 403;
        } else if (path == '/html') {
          request.response.headers.contentType = ContentType.html;
          request.response.add(List.filled(65536, 65));
        } else if (path == '/tiny') {
          request.response.add([0]);
        } else {
          request.response.headers.contentType = ContentType.binary;
          // Deliberately ignore Range, and send more than the requested sample.
          request.response.add(List.filled(262144, 1));
        }
        await request.response.close();
      } catch (_) {
        // Client cancellation is expected for losing / timed-out requests.
      } finally {
        active--;
      }
    }());
  });
  AutoCdnSelector selector() => AutoCdnSelector(
    headers: {
      'Referer': 'https://www.bilibili.com',
      'User-Agent': 'regression-test',
    },
  );
  try {
    var s = selector();
    final watch = Stopwatch()..start();
    check(
      await s.choose(['$base/slow', '$base/fast']) == '$base/fast',
      'Fast candidate must win without waiting for slow one',
    );
    check(watch.elapsedMilliseconds < 400, 'Slow candidate delayed winner');
    s.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    check(maxActive <= 2, 'More than two concurrent probes');

    s = selector();
    check(
      await s.choose([
            '$base/forbidden',
            '$base/html',
            '$base/tiny',
            '$base/fast',
          ]) ==
          '$base/fast',
      'Bad status, HTML, or tiny body accepted',
    );
    s.cancel();

    s = selector();
    watch.reset();
    check(
      await s.choose([
            '$base/slow',
            '$base/slow?2',
          ], budget: const Duration(milliseconds: 60)) ==
          null,
      'Deadline ignored',
    );
    check(watch.elapsedMilliseconds < 300, 'Deadline did not bound body read');
    s.cancel();

    s = selector();
    final pending = s.choose(['$base/slow', '$base/slow?3']);
    s.cancel();
    check(await pending == null, 'Cancelled source returned a winner');
    check(await s.choose(['$base/fast']) == null, 'Cancelled selector reused');

    AutoCdnSelector.remember('$base/old?expired-signature');
    s = selector();
    final before = requests;
    check(
      await s.choose(['$base/new?fresh-signature', '$base/other']) ==
          '$base/new?fresh-signature',
      'Reused expired URL instead of current URL',
    );
    check(requests == before, 'Cached host triggered a new probe');
    s.cancel();
    AutoCdnSelector.resetNetwork();
    s = selector();
    check(
      await s.choose(['$base/forbidden', '$base/fast']) == '$base/fast',
      'Network change did not invalidate host preference',
    );
    s.cancel();
    check(validHeaders, 'Probe headers differ from playback headers');
    print(
      'PASS: race, concurrency, invalid responses, bounded timeout, cancellation, fresh URLs, network reset',
    );
  } finally {
    await subscription.cancel();
    await server.close(force: true);
    await Future.wait(handlers);
  }
}

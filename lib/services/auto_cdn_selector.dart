import 'dart:async';
import 'dart:io';

/// Bounded, cancellable sampling. No player, UI, or audio-session side effects.
/// Cache hosts only: signed media URLs must always come from the current video.
class AutoCdnSelector {
  static final Map<String, DateTime> _good = {};
  static void resetNetwork() => _good.clear();
  static const _ttl = Duration(minutes: 10);
  final Map<String, String> headers;
  final Set<HttpClient> _clients = {};
  final Set<Completer<String?>> _pending = {};
  bool _cancelled = false;

  AutoCdnSelector({required this.headers});

  static String _host(String url) => Uri.parse(url).authority;

  static void remember(String url) {
    _good[_host(url)] = DateTime.now();
    _good.removeWhere((_, time) => DateTime.now().difference(time) > _ttl);
  }

  static void forget(String url) => _good.remove(_host(url));

  void cancel() {
    _cancelled = true;
    for (final pending in _pending.toList()) {
      if (!pending.isCompleted) pending.complete(null);
    }
    for (final client in _clients.toList()) {
      client.close(force: true);
    }
    _clients.clear();
  }

  /// Race at most two small downloads. Expand only when a candidate fails;
  /// one shared deadline bounds DNS, connection, headers, and body together.
  /// A sample is a hint, never a reason to interrupt healthy playback.
  Future<String?> choose(
    List<String> urls, {
    bool useCache = true,
    Duration budget = const Duration(milliseconds: 1200),
  }) async {
    if (_cancelled || urls.isEmpty) return null;
    if (useCache) {
      for (final url in urls) {
        final good = _good[_host(url)];
        if (good != null && DateTime.now().difference(good) < _ttl) {
          return url;
        }
      }
    }
    if (urls.length == 1 && useCache) return urls.first;
    final result = Completer<String?>();
    _pending.add(result);
    final clients = <HttpClient>{};
    var next = 0;
    var running = 0;
    final deadline = Timer(budget, () {
      if (!result.isCompleted) result.complete(null);
    });
    Future<void> worker() async {
      running++;
      try {
        while (!_cancelled && !result.isCompleted && next < urls.length) {
          final url = urls[next++];
          final client = HttpClient()..connectionTimeout = budget;
          clients.add(client);
          _clients.add(client);
          try {
            final request = await client.getUrl(Uri.parse(url));
            if (_cancelled || result.isCompleted) break;
            headers.forEach(request.headers.set);
            request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-65535');
            final response = await request.close();
            if (response.statusCode != 200 && response.statusCode != 206) {
              continue;
            }
            // Never accept an HTML error page or a one-byte response as a
            // successful media sample. Stop reading even if Range was ignored.
            final type = response.headers.contentType?.mimeType ?? '';
            if (type.startsWith('text/') || type.contains('json')) continue;
            var received = 0;
            await for (final chunk in response) {
              if (_cancelled || result.isCompleted) break;
              received += chunk.length;
              if (received >= 65536) {
                result.complete(url);
                break;
              }
            }
          } catch (_) {
            // Try the next candidate silently, within the same deadline.
          } finally {
            client.close(force: true);
            clients.remove(client);
            _clients.remove(client);
          }
        }
      } finally {
        running--;
        if (running == 0 && !result.isCompleted) result.complete(null);
      }
    }

    unawaited(worker());
    unawaited(worker());
    final selected = await result.future;
    deadline.cancel();
    _pending.remove(result);
    for (final client in clients.toList()) {
      client.close(force: true);
      _clients.remove(client);
    }
    return _cancelled ? null : selected;
  }
}

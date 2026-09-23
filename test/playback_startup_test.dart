import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../lib/utils/playback_startup.dart';

void main() {
  for (final sourceFirst in [true, false]) {
    test('startup overlaps both requests; sourceFirst=$sourceFirst', () async {
      final source = Completer<String>();
      final network = Completer<bool>();
      final calls = <String>[];
      final pending = preparePlaybackSource(
        loadSource: () {
          calls.add('source');
          return source.future;
        },
        needsNetworkPreferences: true,
        readIsWiFi: () {
          calls.add('network');
          return network.future;
        },
      );
      expect(calls, ['source', 'network']);
      var done = false;
      final observed = pending.then((value) {
        done = true;
        return value;
      });
      if (sourceFirst) {
        source.complete('selected-source');
      } else {
        network.complete(false);
      }
      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse);
      if (sourceFirst) {
        network.complete(false);
      } else {
        source.complete('selected-source');
      }
      expect(await observed, ('selected-source', false));
    });
  }

  test('cached preferences skip device lookup and preserve source', () async {
    final result = await preparePlaybackSource(
      loadSource: () async => 'fixed-cdn-url',
      needsNetworkPreferences: false,
      readIsWiFi: () => throw StateError('must not be called'),
    );
    expect(result, ('fixed-cdn-url', null));
  });

  test('both asynchronous errors are observed without retrying', () async {
    final source = Completer<String>();
    final network = Completer<bool>();
    final pending = preparePlaybackSource(
      loadSource: () => source.future,
      needsNetworkPreferences: true,
      readIsWiFi: () => network.future,
    );
    final expectation = expectLater(pending, throwsA(isA<ParallelWaitError>()));
    source.completeError(StateError('source failed'));
    network.completeError(StateError('device lookup failed'));
    await expectation;
  });
}

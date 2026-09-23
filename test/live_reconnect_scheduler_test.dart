import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../lib/services/live_reconnect_scheduler.dart';

void main() {
  testWidgets('error burst schedules only one reconnect', (tester) async {
    final scheduler = LiveReconnectScheduler();
    var attempts = 0;
    Future<void> reconnect(bool Function() current) async {
      expect(current(), isTrue);
      attempts++;
    }
    for (var i = 0; i < 20; i++) {
      scheduler.schedule(reconnect);
    }
    await tester.pump(const Duration(seconds: 2));
    expect(attempts, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(attempts, 1);
    await tester.pump(const Duration(seconds: 10));
    expect(attempts, 1);
    scheduler.cancel();
  });

  testWidgets('recovery, pause or source change cancels pending work', (tester) async {
    final scheduler = LiveReconnectScheduler();
    var attempts = 0;
    scheduler.schedule((_) async { attempts++; });
    scheduler.cancel();
    await tester.pump(const Duration(seconds: 4));
    expect(attempts, 0);
    // New errors after cancellation can schedule a fresh attempt.
    scheduler.schedule((_) async { attempts++; });
    await tester.pump(const Duration(seconds: 3));
    expect(attempts, 1);
    scheduler.cancel();
  });

  testWidgets('pause during reopen prevents stale automatic playback', (tester) async {
    final scheduler = LiveReconnectScheduler();
    final gate = Completer<void>();
    var opens = 0;
    var plays = 0;
    Future<void> reconnect(bool Function() current) async {
      opens++;
      await gate.future;
      if (current()) plays++;
    }
    scheduler.schedule(reconnect);
    await tester.pump(const Duration(seconds: 3));
    expect(scheduler.isRunning, isTrue);
    scheduler.schedule(reconnect);
    scheduler.cancel();
    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(opens, 1);
    expect(plays, 0);
    expect(scheduler.isRunning, isFalse);
  });

  testWidgets('failed reopen releases gate without an endless retry loop', (tester) async {
    final scheduler = LiveReconnectScheduler();
    var attempts = 0;
    scheduler.schedule((_) async {
      attempts++;
      throw StateError('network unavailable');
    });
    await tester.pump(const Duration(seconds: 3));
    expect(scheduler.isRunning, isFalse);
    await tester.pump(const Duration(seconds: 30));
    expect(attempts, 1);
    scheduler.schedule((_) async { attempts++; });
    await tester.pump(const Duration(seconds: 3));
    expect(attempts, 2);
    scheduler.cancel();
  });
}

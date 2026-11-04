import 'dart:io';
import 'dart:collection';

import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show VoidCallback;

const MethodChannel _accessibilityChannel = MethodChannel(
  'accessibilibili/accessibility',
);

int _lastPageScrolledNotificationMs = 0;

final _replyReadingTrace = Queue<String>();
final _replyReadingCounts = <String, int>{};

void traceReplyReading(String event, [String details = '']) {
  if (!Platform.isIOS) return;
  _replyReadingCounts.update(event, (count) => count + 1, ifAbsent: () => 1);
  _replyReadingTrace.add(
    '${DateTime.now().millisecondsSinceEpoch} D $event $details',
  );
  if (_replyReadingTrace.length > 240) _replyReadingTrace.removeFirst();
}

Future<void> copyReplyReadingDiagnostics() async {
  traceReplyReading('export');
  final native = Platform.isIOS
      ? await _accessibilityChannel.invokeMethod<String>('replyReadingDiagnostics')
      : 'Not iOS';
  final report = [
    'Accessibilibili Read All diagnostics v1',
    'Dart counters: $_replyReadingCounts',
    ..._replyReadingTrace,
    native ?? 'Native diagnostics unavailable',
  ].join('\n');
  await Clipboard.setData(ClipboardData(text: report));
}

final Map<String, VoidCallback> iosReplyReadingAnchors = {};

void initIosAccessibilityActions() {
  if (!Platform.isIOS) return;

  _accessibilityChannel.setMethodCallHandler((call) async {
    if (call.method == 'readReplyAnchor') {
      final id = call.arguments as String;
      traceReplyReading('anchorReceived',
          'id=$id found=${iosReplyReadingAnchors.containsKey(id)}');
      iosReplyReadingAnchors[id]?.call();
    } else if (call.method == 'magicTap') {
      await PlPlayerController.instance?.togglePlaybackAccessible();
    }
  });
}

/// Tells iOS that a VoiceOver page-scroll gesture has completed.
///
/// UIKit uses UIAccessibility.Notification.pageScrolled for its native
/// VoiceOver scroll feedback. The short debounce prevents a nested local and
/// global scroll bridge from producing duplicate feedback for one gesture.
Future<void> notifyIosVoiceOverPageScrolled() async {
  if (!Platform.isIOS) return;

  final now = DateTime.now().millisecondsSinceEpoch;
  if (now - _lastPageScrolledNotificationMs < 120) {
    traceReplyReading('notificationDebounced');
    return;
  }
  traceReplyReading('notificationSent');
  _lastPageScrolledNotificationMs = now;

  try {
    await _accessibilityChannel.invokeMethod<void>('pageScrolled');
  } catch (_) {
    // Accessibility feedback must never interfere with scrolling itself.
  }
}

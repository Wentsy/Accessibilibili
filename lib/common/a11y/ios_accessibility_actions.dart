import 'dart:io';

import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:flutter/services.dart';

const MethodChannel _accessibilityChannel = MethodChannel(
  'accessibilibili/accessibility',
);

int _lastPageScrolledNotificationMs = 0;

void initIosAccessibilityActions() {
  if (!Platform.isIOS) return;

  _accessibilityChannel.setMethodCallHandler((call) async {
    if (call.method == 'magicTap') {
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
  if (now - _lastPageScrolledNotificationMs < 120) return;
  _lastPageScrolledNotificationMs = now;

  try {
    await _accessibilityChannel.invokeMethod<void>('pageScrolled');
  } catch (_) {
    // Accessibility feedback must never interfere with scrolling itself.
  }
}

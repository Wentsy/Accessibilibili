import 'dart:io';

import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:flutter/services.dart';

const MethodChannel _accessibilityChannel = MethodChannel(
  'accessibilibili/accessibility',
);

void initIosAccessibilityActions() {
  if (!Platform.isIOS) return;

  _accessibilityChannel.setMethodCallHandler((call) async {
    if (call.method == 'magicTap') {
      await PlPlayerController.instance?.togglePlaybackAccessible();
    }
  });
}

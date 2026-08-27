// 🔴 無障礙：全域語音即時反饋工具
import 'package:flutter/semantics.dart';

void a11yAnnounce(String message) {
  try {
    SemanticsService.announce(message, TextDirection.ltr);
  } catch (_) {}
}

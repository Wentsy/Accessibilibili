import 'package:flutter/semantics.dart';

/// 🔴 無障礙：互動操作的即時 VoiceOver 回饋。
///
/// 成功與失敗都使用相同入口，避免不同頁面只顯示 Toast 而沒有語音。
void a11yActionFeedback({
  required String message,
}) {
  try {
    SemanticsService.announce(message, TextDirection.ltr);
  } catch (_) {}
}

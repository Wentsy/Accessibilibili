import 'package:flutter/material.dart';

/// Keeps VoiceOver's accessibility focus and Flutter's real viewport aligned.
///
/// Flutter can move accessibility focus to an offscreen semantic node without
/// automatically scrolling that node into the visible viewport. When that
/// happens, swipe navigation and touch exploration describe different content.
/// Call this from Semantics.onDidGainAccessibilityFocus for list items.
void a11yEnsureVisible(BuildContext context) {
  if (!MediaQuery.accessibleNavigationOf(context)) return;

  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    Scrollable.ensureVisible(
      context,
      alignment: 0.5,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  });
}

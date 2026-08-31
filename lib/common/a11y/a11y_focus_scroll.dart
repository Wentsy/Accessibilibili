import 'package:flutter/material.dart';

/// Keeps VoiceOver's accessibility focus and Flutter's real viewport aligned.
///
/// Flutter can move accessibility focus to an offscreen semantic node without
/// automatically scrolling that node into the visible viewport. When that
/// happens, swipe navigation and touch exploration describe different content.
/// Call this from Semantics.onDidGainAccessibilityFocus for list items.
void a11yEnsureVisible(BuildContext context) {
  if (!MediaQuery.accessibleNavigationOf(context)) return;

  // Do not react to accessibility-focus restoration while a route is being
  // pushed or popped. During a transition VoiceOver may temporarily focus an
  // old semantic node, which must not be allowed to pull the previous page
  // back to the top.
  final route = ModalRoute.of(context);
  if (route != null) {
    final animation = route.animation;
    final secondaryAnimation = route.secondaryAnimation;
    if ((animation != null && animation.status != AnimationStatus.completed) ||
        (secondaryAnimation != null &&
            secondaryAnimation.status != AnimationStatus.dismissed)) {
      return;
    }
  }

  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;

    final renderObject = context.findRenderObject();
    final scrollable = Scrollable.maybeOf(context);
    if (renderObject == null ||
        !renderObject.attached ||
        scrollable == null ||
        !scrollable.position.hasPixels) {
      return;
    }

    // Only scroll when the focused semantic node is actually outside the
    // visible viewport. Previously every focus event used alignment 0.5,
    // which could move an already-visible item and could reset a page when
    // VoiceOver restored focus after navigating back.
    final itemRect = MatrixUtils.transformRect(
      renderObject.getTransformTo(scrollable.context.findRenderObject()),
      renderObject.paintBounds,
    );
    final viewportSize = scrollable.context.size;
    if (viewportSize == null) return;

    final viewportRect = Offset.zero & viewportSize;
    if (viewportRect.overlaps(itemRect)) {
      return;
    }

    Scrollable.ensureVisible(
      context,
      alignment: 0.5,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  });
}

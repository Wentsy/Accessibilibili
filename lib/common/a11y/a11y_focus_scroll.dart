import 'package:flutter/material.dart';

int _a11yFocusScrollSuppressedUntilMs = 0;

/// Temporarily suppresses focus-driven scrolling while a paged list rebuilds.
///
/// iOS VoiceOver may briefly restore accessibility focus to the first semantic
/// node while Flutter rebuilds a list after appending another page. If the
/// first node immediately calls ensureVisible, the viewport is pulled back to
/// the top. A short suppression window lets the semantics tree settle first.
void suppressA11yFocusScroll([
  Duration duration = const Duration(milliseconds: 500),
]) {
  _a11yFocusScrollSuppressedUntilMs =
      DateTime.now().millisecondsSinceEpoch + duration.inMilliseconds;
}

/// Keeps VoiceOver's accessibility focus and Flutter's real viewport aligned.
///
/// Flutter can move accessibility focus to an offscreen semantic node without
/// automatically scrolling that node into the visible viewport. When that
/// happens, swipe navigation and touch exploration describe different content.
/// Call this from Semantics.onDidGainAccessibilityFocus for list items.
void a11yEnsureVisible(BuildContext context) {
  if (!MediaQuery.accessibleNavigationOf(context)) return;
  if (DateTime.now().millisecondsSinceEpoch < _a11yFocusScrollSuppressedUntilMs) {
    return;
  }

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
    final viewportRenderObject = scrollable.context.findRenderObject();
    if (viewportRenderObject == null || !viewportRenderObject.attached) {
      return;
    }

    final itemRect = MatrixUtils.transformRect(
      renderObject.getTransformTo(viewportRenderObject),
      renderObject.paintBounds,
    );
    final viewportRect = viewportRenderObject.paintBounds;
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

import 'package:PiliPlus/common/a11y/ios_accessibility_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Bridges VoiceOver's standard scroll semantic actions to the real Flutter
/// scroll position so three-finger page gestures move the visible viewport.
class VoiceOverPagedScroll extends StatelessWidget {
  const VoiceOverPagedScroll({
    super.key,
    this.controller,
    required this.child,
    this.pageFraction = 0.85,
    this.onScrollBackwardAtStart,
    this.onScrollForwardAtEnd,
    this.nativeFeedScroll = false,
    this.replyHasMore,
    this.replyScrollMetrics = false,
  });

  final ScrollController? controller;
  final Widget child;
  final double pageFraction;
  final VoidCallback? onScrollBackwardAtStart;
  final VoidCallback? onScrollForwardAtEnd;

  /// Opt in only for feeds whose native iOS scroll view must forward vertical
  /// gestures to this node even at an edge. Leave proven reply/live paths alone.
  final bool nativeFeedScroll;
  /// null leaves non-comment scroll paths unchanged.
  final bool? replyHasMore;
  final bool replyScrollMetrics;

  void _page(BuildContext context, {required bool forward}) {
    final scrollController =
        controller ?? PrimaryScrollController.maybeOf(context);
    if (scrollController == null || !scrollController.hasClients) return;

    final position = scrollController.position;
    final delta = position.viewportDimension * pageFraction;
    final target = (position.pixels + (forward ? delta : -delta)).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );

    if ((target - position.pixels).abs() < 1) {
      if (forward) {
        onScrollForwardAtEnd?.call();
      } else {
        onScrollBackwardAtStart?.call();
      }
      return;
    }

    scrollController
        .animateTo(
          target.toDouble(),
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(notifyIosVoiceOverPageScrolled);
  }

  @override
  Widget build(BuildContext context) {
    if (!MediaQuery.accessibleNavigationOf(context)) {
      return child;
    }

    if (replyScrollMetrics) {
      return _ReplyScrollSemantics(
        controller: controller!,
        identifier: replyHasMore != null
            ? 'a11y-reply-scroll|${replyHasMore! ? 'more' : 'end'}'
            : 'a11y-feed-scroll|viewport',
        forward: () => _page(context, forward: true),
        backward: () => _page(context, forward: false),
        child: child,
      );
    }

    return Semantics(
      identifier: replyHasMore != null
          ? 'a11y-reply-scroll|${replyHasMore! ? 'more' : 'end'}'
          : nativeFeedScroll ? 'a11y-feed-scroll|viewport' : null,
      container: true,
      explicitChildNodes: true,
      // Preserve the app's established gesture mapping for feeds as well:
      // three-finger down pages backward / refreshes at the start, while
      // three-finger up pages forward / loads more at the end. The native
      // feed bridge is routing-only; opting in must not invert the actions.
      onScrollUp: () => _page(context, forward: true),
      onScrollDown: () => _page(context, forward: false),
      child: child,
    );
  }
}

class _ReplyScrollSemantics extends SingleChildRenderObjectWidget {
  const _ReplyScrollSemantics({
    required this.controller,
    required this.identifier,
    required this.forward,
    required this.backward,
    required super.child,
  });

  final ScrollController controller;
  final String identifier;
  final VoidCallback forward;
  final VoidCallback backward;

  @override
  _RenderReplyScrollSemantics createRenderObject(BuildContext context) =>
      _RenderReplyScrollSemantics(controller, identifier, forward, backward);

  @override
  void updateRenderObject(BuildContext context, _RenderReplyScrollSemantics renderObject) {
    renderObject.update(controller, identifier, forward, backward);
  }
}

class _RenderReplyScrollSemantics extends RenderProxyBox {
  _RenderReplyScrollSemantics(this.controller, this.identifier, this.forward, this.backward);

  ScrollController controller;
  String identifier;
  VoidCallback forward;
  VoidCallback backward;

  void update(ScrollController next, String id, VoidCallback up, VoidCallback down) {
    if (controller != next) {
      if (attached) controller.removeListener(markNeedsSemanticsUpdate);
      controller = next;
      if (attached) controller.addListener(markNeedsSemanticsUpdate);
    }
    identifier = id;
    forward = up;
    backward = down;
    markNeedsSemanticsUpdate();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    controller.addListener(markNeedsSemanticsUpdate);
  }

  @override
  void detach() {
    controller.removeListener(markNeedsSemanticsUpdate);
    super.detach();
  }

  @override
  void performLayout() {
    super.performLayout();
    // Appended rows and viewport resizing change extents without scrolling.
    markNeedsSemanticsUpdate();
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..isSemanticBoundary = true
      ..explicitChildNodes = true
      ..identifier = identifier
      ..onScrollUp = forward
      ..onScrollDown = backward;
    if (controller.hasClients && controller.position.hasContentDimensions) {
      final position = controller.position;
      // The iOS bridge constructs contentSize from scrollExtentMax. Missing
      // metrics otherwise produce a zero-range native scroll container.
      config
        ..scrollPosition = position.pixels
        ..scrollExtentMin = position.minScrollExtent
        ..scrollExtentMax = position.maxScrollExtent;
    }
  }
}

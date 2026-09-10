import 'package:PiliPlus/common/a11y/ios_accessibility_actions.dart';
import 'package:flutter/material.dart';

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
  });

  final ScrollController? controller;
  final Widget child;
  final double pageFraction;
  final VoidCallback? onScrollBackwardAtStart;
  final VoidCallback? onScrollForwardAtEnd;

  /// Opt in only for feeds whose native iOS scroll view must forward vertical
  /// gestures to this node even at an edge. Leave proven reply/live paths alone.
  final bool nativeFeedScroll;

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

    return Semantics(
      identifier: nativeFeedScroll ? 'a11y-feed-scroll|viewport' : null,
      container: true,
      explicitChildNodes: true,
      // Semantic directions describe the content position, not finger motion:
      // iOS three-finger down -> scrollUp -> toward minScrollExtent.
      // Keep legacy mapping unchanged outside the explicitly opted-in feeds.
      onScrollUp: () => _page(context, forward: !nativeFeedScroll),
      onScrollDown: () => _page(context, forward: nativeFeedScroll),
      child: child,
    );
  }
}

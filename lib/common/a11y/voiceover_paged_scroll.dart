import 'package:flutter/material.dart';

/// Bridges VoiceOver's standard scroll semantic actions to the real Flutter
/// scroll position so three-finger page gestures move the visible viewport.
class VoiceOverPagedScroll extends StatelessWidget {
  const VoiceOverPagedScroll({
    super.key,
    this.controller,
    required this.child,
    this.pageFraction = 0.85,
  });

  final ScrollController? controller;
  final Widget child;
  final double pageFraction;

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

    if ((target - position.pixels).abs() < 1) return;

    scrollController.animateTo(
      target.toDouble(),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!MediaQuery.accessibleNavigationOf(context)) {
      return child;
    }

    return Semantics(
      container: true,
      explicitChildNodes: true,
      onScrollUp: () => _page(context, forward: true),
      onScrollDown: () => _page(context, forward: false),
      child: child,
    );
  }
}

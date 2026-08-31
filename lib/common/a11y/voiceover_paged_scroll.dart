import 'package:flutter/material.dart';

/// Bridges VoiceOver's standard scroll semantic actions to the real Flutter
/// scroll position so three-finger page gestures move the visible viewport.
class VoiceOverPagedScroll extends StatelessWidget {
  const VoiceOverPagedScroll({
    super.key,
    required this.controller,
    required this.child,
    this.pageFraction = 0.85,
  });

  final ScrollController controller;
  final Widget child;
  final double pageFraction;

  void _page({required bool forward}) {
    if (!controller.hasClients) return;

    final position = controller.position;
    final delta = position.viewportDimension * pageFraction;
    final target = (position.pixels + (forward ? delta : -delta)).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );

    if ((target - position.pixels).abs() < 1) return;

    controller.animateTo(
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
      onScrollUp: () => _page(forward: true),
      onScrollDown: () => _page(forward: false),
      child: child,
    );
  }
}

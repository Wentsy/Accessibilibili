import 'dart:io' show Platform;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:material_ui/material_ui.dart';

const Set<PointerDeviceKind> desktopDragDevices = {
  .touch,
  .mouse,
  .trackpad,
  .stylus,
  .invertedStylus,
  .unknown,
};

class CustomScrollBehavior extends MaterialScrollBehavior {
  const CustomScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    Widget result = child;

    if (Platform.isAndroid) {
      result = StretchingOverscrollIndicator(
        axisDirection: details.direction,
        clipBehavior: details.decorationClipBehavior ?? .hardEdge,
        child: result,
      );
    }

    // Apply the VoiceOver paging bridge app-wide to every vertical Scrollable.
    // This covers CustomScrollView, ListView, GridView and future list pages
    // without requiring each screen to opt in separately.
    if (Platform.isIOS &&
        axisDirectionToAxis(details.direction) == Axis.vertical) {
      result = _VoiceOverGlobalScrollBridge(
        direction: details.direction,
        controller: details.controller,
        child: result,
      );
    }

    return result;
  }

  @override
  Set<PointerDeviceKind> get dragDevices => desktopDragDevices;
}

class _VoiceOverGlobalScrollBridge extends StatelessWidget {
  const _VoiceOverGlobalScrollBridge({
    required this.direction,
    required this.controller,
    required this.child,
  });

  final AxisDirection direction;
  final ScrollController? controller;
  final Widget child;

  AxisDirection get _oppositeDirection => switch (direction) {
    AxisDirection.up => AxisDirection.down,
    AxisDirection.down => AxisDirection.up,
    AxisDirection.left => AxisDirection.right,
    AxisDirection.right => AxisDirection.left,
  };

  void _page(BuildContext context, {required bool forward}) {
    if (!MediaQuery.accessibleNavigationOf(context)) return;

    final scrollController = controller;
    if (scrollController != null && scrollController.hasClients) {
      final position = scrollController.position;
      final amount = position.viewportDimension * 0.85;
      final sign = switch (direction) {
        AxisDirection.down || AxisDirection.right => 1.0,
        AxisDirection.up || AxisDirection.left => -1.0,
      };
      final delta = amount * sign * (forward ? 1.0 : -1.0);
      final target = (position.pixels + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if ((target - position.pixels).abs() < 1) return;
      scrollController.animateTo(
        target.toDouble(),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
      return;
    }

    // ScrollViews with an internally-created controller can still use
    // Flutter's standard page ScrollAction. It scrolls the nearest Scrollable
    // and falls back to the PrimaryScrollController when appropriate.
    ScrollAction().invoke(
      ScrollIntent(
        direction: forward ? direction : _oppositeDirection,
        type: ScrollIncrementType.page,
      ),
      context,
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

class NoOverscrollIndicator extends CustomScrollBehavior {
  const NoOverscrollIndicator();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}

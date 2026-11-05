import 'package:PiliPlus/common/a11y/ios_accessibility_actions.dart';
import 'package:PiliPlus/common/a11y/voiceover_paged_scroll.dart';
import 'package:PiliPlus/pages/common/reply_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/semantics.dart' show OrdinalSortKey;
import 'package:get/get.dart';

/// Only explicit page requests emit pageScrolled, never background prefetch.
class ReplyPagedScroll extends StatelessWidget {
  const ReplyPagedScroll({super.key, required this.controller, required this.child,
    this.allowRefresh = false});
  final ReplyController controller;
  final Widget child;
  // Refresh shares the comment viewport; do not add a feed-routing ancestor.
  final bool allowRefresh;

  @override
  Widget build(BuildContext context) => useIosReplyReading(context)
      ? NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.depth == 0 &&
                notification.metrics.extentAfter < notification.metrics.viewportDimension * 2) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted && !controller.isClosed &&
                    ModalRoute.of(context)?.isCurrent != false) {
                  controller.onLoadMore();
                }
              });
            }
            return false;
          },
          child: child,
        )
      : Obx(() {
    final data = controller.loadingState.value.dataOrNull;
    return VoiceOverPagedScroll(
      controller: controller.scrollController,
      replyScrollMetrics: true,
      replyHasMore: data != null && !controller.isEnd,
      onScrollBackwardAtStart: allowRefresh
          ? () { controller.onA11yRefresh(label: '評論'); }
          : null,
      onScrollForwardAtEnd: () async {
        final before = controller.loadingState.value.dataOrNull?.length ?? 0;
        await controller.retryLoadMore();
        if (!context.mounted || controller.isClosed ||
            ModalRoute.of(context)?.isCurrent == false ||
            !MediaQuery.accessibleNavigationOf(context)) return;
        if ((controller.loadingState.value.dataOrNull?.length ?? 0) > before) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!context.mounted || controller.isClosed ||
                ModalRoute.of(context)?.isCurrent == false) return;
            final scroll = controller.scrollController;
            if (!scroll.hasClients) return;
            final position = scroll.position;
            final target = (position.pixels + position.viewportDimension * 0.85)
                .clamp(position.minScrollExtent, position.maxScrollExtent);
            await scroll.animateTo(
              target.toDouble(),
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
            );
            await WidgetsBinding.instance.endOfFrame;
            if (context.mounted && !controller.isClosed &&
                ModalRoute.of(context)?.isCurrent != false &&
                MediaQuery.accessibleNavigationOf(context)) {
              notifyIosVoiceOverPageScrolled();
            }
          });
          WidgetsBinding.instance.ensureVisualUpdate();
        }
      },
      child: child,
    );
  });
}

/// Status only: no retry button or tap action is added to comment traversal.
class ReplyPaginationStatus extends StatelessWidget {
  const ReplyPaginationStatus({super.key, required this.controller});
  final ReplyController controller;

  @override
  Widget build(BuildContext context) => Obx(() {
    final failed = controller.loadMoreFailed.value;
    controller.loadingState.value; // Observe append/end changes as well.
    if (controller.isEnd) {
      return Semantics(`r`n        sortKey: OrdinalSortKey(double.maxFinite),
        child: Text('没有更多了'),
      );
    }
    // A transient loading row must not become Read All's current position:
    // newly appended replies would then be inserted before that position.
    if (useIosReplyReading(context) && !failed) {
      return const ExcludeSemantics(child: Text('正在載入更多評論'));
    }
    return Semantics(
      sortKey: OrdinalSortKey(double.maxFinite),
      onDidGainAccessibilityFocus: () {
        if (failed) controller.retryLoadMore();
      },
      child: Text(failed ? '評論暫時載入失敗' : '正在載入更多評論'),
    );
  });
}

/// Shared viewport for article/music/match/general comment entry points.
class ReplyScrollView extends StatelessWidget {
  const ReplyScrollView({super.key, required this.replyController,
    required this.slivers, this.physics});
  final ReplyController replyController;
  final List<Widget> slivers;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    final accessible = MediaQuery.accessibleNavigationOf(context);
    return ReplyPagedScroll(
      controller: replyController,
      allowRefresh: true,
      child: CustomScrollView(
        controller: accessible ? replyController.scrollController : null,
        cacheExtent: accessible ? MediaQuery.sizeOf(context).height * 8 : null,
        physics: physics,
        slivers: slivers,
      ),
    );
  }
}

bool useIosReplyReading(BuildContext context) =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS &&
    MediaQuery.accessibleNavigationOf(context);

/// Keep loaded rows mounted while VoiceOver traverses the list. Network
/// pagination is driven by focus/scroll progress, never by building the footer.
class ReplyReadingSliver extends StatelessWidget {
  const ReplyReadingSliver({
    super.key,
    required this.itemBuilder,
    required this.itemCount,
    this.findChildIndexCallback,
  });

  final IndexedWidgetBuilder itemBuilder;
  final int itemCount;
  final int? Function(Key)? findChildIndexCallback;

  @override
  Widget build(BuildContext context) {
    if (!useIosReplyReading(context)) {
      return SliverList.builder(
        itemBuilder: itemBuilder,
        itemCount: itemCount,
        findChildIndexCallback: findChildIndexCallback,
      );
    }
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < itemCount; index++)
            itemBuilder(context, index),
        ],
      ),
    );
  }
}

import 'package:PiliPlus/common/a11y/ios_accessibility_actions.dart';
import 'package:PiliPlus/common/a11y/voiceover_paged_scroll.dart';
import 'package:PiliPlus/pages/common/reply_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show OrdinalSortKey;
import 'package:get/get.dart';

/// Only explicit page requests emit pageScrolled, never background prefetch.
class ReplyPagedScroll extends StatelessWidget {
  const ReplyPagedScroll({super.key, required this.controller, required this.child,
    this.allowRefresh = false});
  final ReplyController controller;
  final Widget child;
  // Outer comments opt in; nested replies retain their existing behavior.
  final bool allowRefresh;

  @override
  Widget build(BuildContext context) => Obx(() {
    final data = controller.loadingState.value.dataOrNull;
    final paged = VoiceOverPagedScroll(
      controller: controller.scrollController,
      replyHasMore: data != null && !controller.isEnd,
      onScrollForwardAtEnd: () async {
        final before = controller.loadingState.value.dataOrNull?.length ?? 0;
        await controller.retryLoadMore();
        if (!context.mounted || controller.isClosed ||
            ModalRoute.of(context)?.isCurrent == false ||
            !MediaQuery.accessibleNavigationOf(context)) return;
        if ((controller.loadingState.value.dataOrNull?.length ?? 0) > before) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted && ModalRoute.of(context)?.isCurrent != false) {
              notifyIosVoiceOverPageScrolled();
            }
          });
          WidgetsBinding.instance.ensureVisualUpdate();
        }
      },
      child: child,
    );
    if (!allowRefresh) return paged;
    // Separate the native explicit-gesture route from Read All's quiet
    // reply wrapper. Keep its more/end marker intact for continuous reading.
    return VoiceOverPagedScroll(
      controller: controller.scrollController,
      nativeFeedScroll: true,
      onScrollBackwardAtStart: () {
        controller.onA11yRefresh(label: '評論');
      },
      onScrollForwardAtEnd: controller.onA11yReplyLoadMore,
      child: paged,
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
    if (controller.isEnd) return const Text('没有更多了');
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

import 'package:PiliPlus/common/a11y/ios_accessibility_actions.dart';
import 'package:PiliPlus/common/a11y/voiceover_paged_scroll.dart';
import 'package:PiliPlus/pages/common/reply_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Only explicit page requests emit pageScrolled, never background prefetch.
class ReplyPagedScroll extends StatelessWidget {
  const ReplyPagedScroll({super.key, required this.controller, required this.child});
  final ReplyController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) => Obx(() {
    final data = controller.loadingState.value.dataOrNull;
    return VoiceOverPagedScroll(
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
      sortKey: const OrdinalSortKey(double.maxFinite),
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
      child: CustomScrollView(
        controller: accessible ? replyController.scrollController : null,
        cacheExtent: accessible ? MediaQuery.sizeOf(context).height * 8 : null,
        physics: physics,
        slivers: slivers,
      ),
    );
  }
}

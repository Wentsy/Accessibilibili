import 'package:PiliPlus/common/a11y/ios_accessibility_actions.dart';
import 'package:PiliPlus/common/a11y/voiceover_paged_scroll.dart';
import 'package:PiliPlus/pages/common/reply_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show OrdinalSortKey;
import 'package:get/get.dart';

/// One in-flight turn owns loading, scrolling and the completion notification.
class ReplyPagedScroll extends StatefulWidget {
  const ReplyPagedScroll({super.key, required this.controller, required this.child,
    this.allowRefresh = false});
  final ReplyController controller;
  final Widget child;
  final bool allowRefresh;

  @override
  State<ReplyPagedScroll> createState() => _ReplyPagedScrollState();
}

class _ReplyPagedScrollState extends State<ReplyPagedScroll> {
  Future<void>? _turn;

  bool get _active => mounted && !widget.controller.isClosed &&
      ModalRoute.of(context)?.isCurrent != false &&
      MediaQuery.accessibleNavigationOf(context);

  Future<void> _forward() {
    traceReplyReading('forward', 'busy=${_turn != null} active=$_active');
    return _turn ??= _advance().whenComplete(() => _turn = null);
  }

  Future<void> _advance() async {
    final controller = widget.controller;
    final scroll = controller.scrollController;
    traceReplyReading('advanceStart',
        'count=${controller.loadingState.value.dataOrNull?.length} end=${controller.isEnd}');
    if (!_active || !scroll.hasClients) return;

    // A prefetch may already have appended data while native semantics still
    // reports the old boundary. Layout first; do not require the count to grow.
    await WidgetsBinding.instance.endOfFrame;
    if (!_active || !scroll.hasClients) return;
    if (scroll.position.extentAfter < 1 && !controller.isEnd) {
      traceReplyReading('boundaryLoad');
      await controller.retryLoadMore();
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!_active || !scroll.hasClients) return;
    final position = scroll.position;
    final before = position.pixels;
    final target = (before + position.viewportDimension * 0.85)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    traceReplyReading('advanceTarget',
        'before=$before target=$target max=${position.maxScrollExtent} '
        'count=${controller.loadingState.value.dataOrNull?.length} end=${controller.isEnd}');
    if (target - before < 1) return;

    await scroll.animateTo(
      target.toDouble(),
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
    );
    // The animation's Future can complete before the new semantic tree is sent.
    await WidgetsBinding.instance.endOfFrame;
    traceReplyReading('advanceComplete',
        'active=$_active pixels=${scroll.hasClients ? scroll.position.pixels : null}');
    if (_active) await notifyIosVoiceOverPageScrolled();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller.scrollController,
    builder: (context, _) => Obx(() {
    final controller = widget.controller;
    final data = controller.loadingState.value.dataOrNull;
    final paged = VoiceOverPagedScroll(
      controller: controller.scrollController,
      // Server pagination being finished does not mean the viewport is at
      // the last loaded comment. Native scroll metrics can report zero range.
      replyHasMore: data != null && (!controller.isEnd ||
          (controller.scrollController.hasClients &&
           controller.scrollController.position.extentAfter > 1)),
      onScrollForward: _forward,
      child: widget.child,
    );
    if (!widget.allowRefresh) return paged;
    return VoiceOverPagedScroll(
      controller: controller.scrollController,
      nativeFeedScroll: true,
      onScrollBackwardAtStart: () {
        controller.onA11yRefresh(label: '評論');
      },
      onScrollForwardAtEnd: controller.onA11yReplyLoadMore,
      child: paged,
    );
    }),
  );
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

import 'package:flutter/semantics.dart';
import 'package:PiliPlus/common/a11y/reply_semantics.dart';
import 'package:PiliPlus/common/a11y/voiceover_paged_scroll.dart';
import 'package:PiliPlus/common/skeleton/video_reply.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/flutter/refresh_indicator.dart';
import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/sliver/sliver_floating_header.dart';
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show ReplyInfo;
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/pages/common/fab_mixin.dart';
import 'package:PiliPlus/pages/main_reply/controller.dart';
import 'package:PiliPlus/pages/video/reply/widgets/reply_item_grpc.dart';
import 'package:PiliPlus/pages/video/reply_reply/view.dart';
import 'package:PiliPlus/utils/extension/widget_ext.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:PiliPlus/utils/num_utils.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:easy_debounce/easy_throttle.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class MainReplyPage extends StatefulWidget {
  const MainReplyPage({super.key});

  @override
  State<MainReplyPage> createState() => _MainReplyPageState();

  static void toMainReplyPage({
    required int oid,
    required int replyType,
  }) {
    Get.toNamed(
      '/mainReply',
      arguments: {
        'oid': oid,
        'replyType': replyType,
      },
    );
  }
}

class _MainReplyPageState extends State<MainReplyPage>
    with SingleTickerProviderStateMixin, BaseFabMixin, FabMixin {
  final _controller = Get.put(
    MainReplyController(),
    tag: Utils.generateRandomString(8),
  );

  late EdgeInsets padding;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    padding = MediaQuery.viewPaddingOf(context);
  }

  String _a11yLabel(ReplyInfo item) {
    final hasPic = item.content.pictures.isNotEmpty;
    return '${item.member.name} 說：${item.content.message}'
        '${hasPic ? '，[圖片]' : ''}'
        '${item.like > 0 ? '，${item.like} 個讚' : ''}'
        '${item.count > 0 ? '，共 ${item.count} 條回覆' : ''}';
  }

  void _replyToTarget() {
    try {
      feedBack();
      _controller.onReply(
        null,
        oid: _controller.oid,
        replyType: _controller.replyType,
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final accessibleNavigation = MediaQuery.accessibleNavigationOf(context);
    return SimpleScaffold(
      appBar: AppBar(title: const Text('查看评论')),
      body: fabAnimWrapper(
        child: refreshIndicator(
          onRefresh: _controller.onRefresh,
          child: Padding(
            padding: EdgeInsets.only(
              left: padding.left,
              right: padding.right,
            ),
            child: VoiceOverPagedScroll(
              controller: _controller.scrollController,
              child: CustomScrollView(
                controller: _controller.scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                cacheExtent: accessibleNavigation
                    ? MediaQuery.sizeOf(context).height
                    : null,
                slivers: [
                  buildReplyHeader(colorScheme),
                  if (accessibleNavigation)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const .fromLTRB(12, 8, 12, 4),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.icon(
                            onPressed: _replyToTarget,
                            icon: const Icon(Icons.reply),
                            label: const Text('發表評論'),
                          ),
                        ),
                      ),
                    ),
                  Obx(
                    () => _buildBody(
                      colorScheme,
                      _controller.loadingState.value,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ).constraintWidth(),
      ),
      // Keep the composer reachable, but do not let a floating semantic sibling
      // interrupt VoiceOver Read All while comments still have more content.
      // In accessibility mode the same action is exposed inline above the list.
      fab: accessibleNavigation
          ? null
          : SlideTransition(
              position: fabAnimation,
              child: Padding(
                padding: .only(
                  right: kFloatingActionButtonMargin + padding.right,
                  bottom: kFloatingActionButtonMargin + padding.bottom,
                ),
                child: FloatingActionButton(
                  heroTag: null,
                  onPressed: _replyToTarget,
                  tooltip: '评论',
                  child: const Icon(Icons.reply),
                ),
              ),
            ),
    );
  }

  Widget _buildBody(
    ColorScheme colorScheme,
    LoadingState<List<ReplyInfo>?> loadingState,
  ) {
    return switch (loadingState) {
      Loading() => SliverPrototypeExtentList.builder(
        itemCount: 10,
        itemBuilder: (_, _) => const VideoReplySkeleton(),
        prototypeItem: const VideoReplySkeleton(),
      ),
      Success(:final response) =>
        response != null && response.isNotEmpty
            ? SliverList.builder(
                itemCount: response.length + 1,
                itemBuilder: (context, index) {
                  if (index == response.length) {
                    _controller.onLoadMore();
                    return Container(
                      alignment: Alignment.center,
                      margin: EdgeInsets.only(bottom: padding.bottom),
                      height: 125,
                      child: Text(
                        _controller.isEnd ? '没有更多了' : '加载中...',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.outline,
                        ),
                      ),
                    );
                  }

                  final item = response[index];
                  final reply = ReplyItemGrpc(
                    key: ValueKey(item.id),
                    replyItem: item,
                    replyLevel: 1,
                    a11ySortKey: OrdinalSortKey((index + 1).toDouble()),
                    replyReply: (replyItem, id) =>
                        replyReply(context, replyItem, id, colorScheme),
                    onReply: _controller.onReply,
                    onDelete: (reply, subIndex) =>
                        _controller.onRemove(index, reply, subIndex),
                    upMid: _controller.upMid,
                    onCheckReply: (reply) =>
                        _controller.onCheckReply(reply, isManual: true),
                    onToggleTop: (reply) => _controller.onToggleTop(
                      reply,
                      index,
                      _controller.oid,
                      _controller.replyType,
                    ),
                  );

                  return ReplyA11ySemantics(
                    key: ValueKey('main-reply-${item.id}'),
                    replyItem: item,
                    onAccessibilityFocus: () {
                      if (index >= response.length - 5) {
                        _controller.onLoadMore();
                      }
                    },
                    label: _a11yLabel(item),
                    onTap: item.count.toInt() > 0
                        ? () => replyReply(
                            context,
                            item,
                            null,
                            colorScheme,
                          )
                        : () => _controller.onReply(item),
                    onTapHint: item.count.toInt() > 0
                        ? '點兩下展開回覆'
                        : '點兩下回覆這條評論',
                    child: reply,
                  );
                },
              )
            : HttpError(
                errMsg: '还没有评论',
                onReload: _controller.onReload,
              ),
      Error(:final errMsg) => HttpError(
        errMsg: errMsg,
        onReload: _controller.onReload,
      ),
    };
  }

  Widget buildReplyHeader(ColorScheme colorScheme) {
    final secondary = colorScheme.secondary;
    return SliverFloatingHeaderWidget(
      backgroundColor: colorScheme.surface,
      child: Padding(
        padding: const .fromLTRB(12, 2.5, 6, 2.5),
        child: Row(
          mainAxisAlignment: .spaceBetween,
          children: [
            Obx(
              () {
                final count = _controller.count.value;
                return Text(
                  '${count == -1 ? 0 : NumUtils.numFormat(count)}条回复',
                );
              },
            ),
            TextButton.icon(
              style: Style.buttonStyle,
              onPressed: _controller.queryBySort,
              icon: Icon(Icons.sort, size: 16, color: secondary),
              label: Obx(
                () => Text(
                  _controller.sortType.value.descShort,
                  style: TextStyle(fontSize: 13, color: secondary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void replyReply(
    BuildContext context,
    ReplyInfo replyItem,
    int? id,
    ColorScheme colorScheme,
  ) {
    EasyThrottle.throttle('replyReply', const Duration(milliseconds: 500), () {
      int oid = replyItem.oid.toInt();
      int rpid = replyItem.id.toInt();
      Get.to(
        SimpleScaffold(
          appBar: AppBar(
            title: const Text('评论详情'),
            shape: Border(
              bottom: BorderSide(
                color: colorScheme.outline.withValues(alpha: 0.1),
              ),
            ),
          ),
          body: ViewSafeArea(
            child: VideoReplyReplyPanel(
              enableSlide: false,
              id: id,
              oid: oid,
              rpid: rpid,
              isVideoDetail: false,
              replyType: _controller.replyType,
              firstFloor: replyItem,
              upMid: _controller.upMid,
            ),
          ).constraintWidth(),
        ),
        routeName: 'dynamicDetail-Copy',
      );
    });
  }
}

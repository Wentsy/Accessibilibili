import 'package:flutter/semantics.dart';
import 'package:PiliPlus/common/a11y/reply_semantics.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:PiliPlus/common/skeleton/video_reply.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/colored_box_transition.dart';
import 'package:PiliPlus/common/widgets/flutter/refresh_indicator.dart';
import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/common/widgets/scaffold/mini_scaffold.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/simple_colored_box.dart';
import 'package:PiliPlus/common/widgets/sliver/sliver_pinned_header.dart';
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show ReplyInfo;
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/pages/common/slide/common_slide_page.dart';
import 'package:PiliPlus/pages/video/reply/widgets/reply_item_grpc.dart';
import 'package:PiliPlus/pages/video/reply_reply/controller.dart';
import 'package:PiliPlus/utils/app_scheme.dart';
import 'package:PiliPlus/utils/extension/widget_ext.dart';
import 'package:PiliPlus/utils/num_utils.dart';
import 'package:PiliPlus/utils/parse_string.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:extended_nested_scroll_view/extended_nested_scroll_view.dart';
import 'package:fixnum/fixnum.dart' show Int64;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

class VideoReplyReplyPanel extends CommonSlidePage {
  const VideoReplyReplyPanel({
    super.key,
    super.enableSlide,
    this.id,
    required this.oid,
    required this.rpid,
    this.dialog,
    this.firstFloor,
    required this.isVideoDetail,
    required this.replyType,
    this.isNested = false,
    this.upMid,
  });
  final int? id;
  final int oid;
  final int rpid;
  final int? dialog;
  final ReplyInfo? firstFloor;
  final bool isVideoDetail;
  final int replyType;
  final bool isNested;
  final Int64? upMid;

  @override
  State<VideoReplyReplyPanel> createState() => _VideoReplyReplyPanelState();

  static Future<void>? toReply({
    required int oid,
    required int rootId,
    String? rpIdStr,
    required int type,
    Uri? uri,
  }) {
    final rpId = parseIntOrNull(rpIdStr);
    return Get.to(
      arguments: {
        'oid': oid,
        'rpid': rootId,
        'id': ?rpId,
        'type': type,
        'enterUri': ?uri?.toString(), // save panel
      },
      () => SimpleScaffold(
        appBar: AppBar(
          title: const Text('评论详情'),
          actions: [
            IconButton(
              tooltip: '前往',
              onPressed: uri == null
                  ? null
                  : () => PiliScheme.routePush(uri, businessId: type),
              icon: const Icon(Icons.open_in_browser),
            ),
          ],
        ),
        body: ViewSafeArea(
          child: VideoReplyReplyPanel(
            enableSlide: false,
            oid: oid,
            rpid: rootId,
            isVideoDetail: false,
            replyType: type,
            firstFloor: null,
            id: rpId,
          ),
        ).constraintWidth(),
      ),
    );
  }
}

class _VideoReplyReplyPanelState extends State<VideoReplyReplyPanel>
    with SingleTickerProviderStateMixin, CommonSlideMixin {
  late VideoReplyReplyController _controller;
  late final _tag = Utils.makeHeroTag('${widget.rpid}${widget.dialog}');
  Animation<Color?>? _colorAnimation;

  late final bool isDialogue = widget.dialog != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _colorAnimation = null;
    _controller
      ..didChangeDependencies(context)
      ..nestedController = null;
  }

  @override
  void initState() {
    super.initState();
    _controller = Get.put(
      VideoReplyReplyController(
        hasRoot: widget.firstFloor != null,
        id: widget.id,
        oid: widget.oid,
        rpid: widget.rpid,
        dialog: widget.dialog,
        replyType: widget.replyType,
      ),
      tag: _tag,
    );
  }

  @override
  void dispose() {
    Get.delete<VideoReplyReplyController>(tag: _tag);
    super.dispose();
  }

  String _a11yLabel(ReplyInfo item) {
    final hasPic = item.content.pictures.isNotEmpty;
    return '${item.member.name} 說：${item.content.message}'
        '${hasPic ? '，[圖片]' : ''}'
        '${item.like > 0 ? '，${item.like} 個讚' : ''}'
        '${item.count > 0 ? '，共 ${item.count} 條回覆' : ''}';
  }

  @override
  Widget buildPage(ThemeData theme) {
    Widget child() => enableSlide ? slideList(theme) : buildList(theme);
    return SimpleColoredBox(
      color: theme.canvasColor,
      child: MiniScaffold(
        body: Stack(
          children: [
            widget.isVideoDetail
            ? Column(
                children: [
                  Container(
                    height: 45,
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          width: 1,
                          color: theme.dividerColor.withValues(alpha: 0.1),
                        ),
                      ),
                    ),
                    padding: const EdgeInsets.only(left: 12, right: 2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text(isDialogue ? '对话列表' : '评论详情'),
                        IconButton(
                          tooltip: '关闭',
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: Get.back,
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: child()),
                ],
              )
            : child(),
            Positioned(
              right: 16,
              bottom: 16 + MediaQuery.paddingOf(context).bottom,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Obx(() {
                    _controller.loadingState.value;
                    if (_controller.isEnd) {
                      return const SizedBox.shrink();
                    }
                    return Semantics(
                      excludeSemantics: true,
                      sortKey: const OrdinalSortKey(0.4),
                      button: true,
                      label: '載入更多回覆',
                      child: FloatingActionButton.small(
                        heroTag: 'loadMoreRepliesSub',
                        onPressed: () {
                          feedBack();
                          final sc = scrollController;
                          if (sc.hasClients) {
                            sc.animateTo(
                              sc.position.maxScrollExtent,
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeOut,
                            );
                          }
                          _controller.onLoadMore();
                        },
                        tooltip: '载入更多回复',
                        child: const Icon(Icons.unfold_more),
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                  Semantics(
                    excludeSemantics: true,
                    sortKey: const OrdinalSortKey(0.5),
                    button: true,
                    label: '發表回覆',
                    child: FloatingActionButton(
                      heroTag: 'replyReplyFab',
                      onPressed: () {
                        final root = widget.firstFloor ?? _controller.firstFloor.value;
                        if (root != null) {
                          feedBack();
                          _controller.onReply(root, index: 0);
                        } else {
                          SmartDialog.showToast('請先等待評論載入');
                        }
                      },
                      tooltip: '发表回复',
                      child: const Icon(Icons.reply),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  ReplyInfo? get firstFloor =>
      widget.firstFloor ?? _controller.firstFloor.value;

  // A reply thread must own its viewport. Reusing the parent video's
  // nested scroll position makes VoiceOver focus move independently from what
  // is actually visible on screen.
  ScrollController get scrollController => _controller.scrollController;

  @override
  Widget buildList(ThemeData theme) {
    return refreshIndicator(
      onRefresh: _controller.onRefresh,
      isClampingScrollPhysics: widget.isNested,
      child: CustomScrollView(
        key: PageStorageKey('reply-thread-${widget.rpid}-${widget.dialog ?? 0}'),
        cacheExtent: MediaQuery.accessibleNavigationOf(context) ? 400 : 3000,
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (!isDialogue) ...[
            if ((widget.firstFloor ?? _controller.firstFloor.value)
                case final firstFloor?)
              _header(theme, firstFloor)
            else
              Obx(() {
                final firstFloor = _controller.firstFloor.value;
                if (firstFloor == null) {
                  return const SliverToBoxAdapter();
                }
                return _header(theme, firstFloor);
              }),
            _sortWidget(theme.colorScheme),
          ],
          Obx(
            () => _buildBody(theme.colorScheme, _controller.loadingState.value),
          ),
        ],
      ),
    );
  }

  Widget _header(ThemeData theme, ReplyInfo firstFloor) {
    final child = ReplyItemGrpc(
      replyItem: firstFloor,
      replyLevel: 2,
      needDivider: false,
      onReply: (replyItem) => _controller.onReply(replyItem, index: -1),
      upMid: widget.upMid ?? _controller.upMid,
      onCheckReply: (item) =>
          _controller.onCheckReply(item, isManual: true),
    );
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: ReplyA11ySemantics(
            replyItem: firstFloor,
            label: _a11yLabel(firstFloor),
            onTap: () => _controller.onReply(firstFloor, index: -1),
            onTapHint: '點兩下回覆這條評論',
            child: child,
          ),
        ),
        SliverToBoxAdapter(
          child: Divider(
            height: 20,
            color: theme.dividerColor.withValues(alpha: 0.1),
            thickness: 6,
          ),
        ),
      ],
    );
  }

  Widget _sortWidget(ColorScheme colorScheme) {
    return SliverPinnedHeader(
      backgroundColor: colorScheme.surface,
      child: Padding(
        padding: const .fromLTRB(12, 2.5, 6, 2.5),
        child: Row(
          mainAxisAlignment: .spaceBetween,
          children: [
            Obx(
              () {
                final count = _controller.count.value;
                return count != -1
                    ? Text(
                        '相关回复共${NumUtils.numFormat(count)}条',
                        style: const TextStyle(fontSize: 13),
                      )
                    : const SizedBox.shrink();
              },
            ),
            TextButton.icon(
              style: Style.buttonStyle,
              onPressed: _controller.queryBySort,
              icon: Icon(Icons.sort, size: 16, color: colorScheme.secondary),
              label: Obx(
                () => Text(
                  _controller.sortType.value.label,
                  style: TextStyle(fontSize: 13, color: colorScheme.secondary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    ColorScheme colorScheme,
    LoadingState<List<ReplyInfo>?> loadingState,
  ) {
    final jumpIndex = _controller.index.value;
    return switch (loadingState) {
      Loading() => SliverPrototypeExtentList.builder(
        prototypeItem: const VideoReplySkeleton(),
        itemBuilder: (_, _) => const VideoReplySkeleton(),
        itemCount: 8,
      ),
      Success(:final response!) =>
        MediaQuery.accessibleNavigationOf(context)
            ? SliverList.builder(
                itemBuilder: (context, index) {
          if (index == response.length) {
            _controller.onLoadMore();
            return Container(
              height: 125,
              alignment: Alignment.center,
              margin: .only(bottom: MediaQuery.viewPaddingOf(context).bottom),
              child: Text(
                _controller.isEnd ? '没有更多了' : '加载中...',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.outline,
                ),
              ),
            );
          }
          final item = response[index];
          final reply = _replyItem(context, item, index);
          final child = ReplyA11ySemantics(
            replyItem: item,
            label: _a11yLabel(item),
            onTap: () => _controller.onReply(item, index: index),
            onTapHint: '點兩下回覆這條評論',
            child: reply,
          );
          if (jumpIndex == index) {
            return KeyedSubtree(
              key: ValueKey('reply-${item.id}'),
              child: ColoredBoxTransition(
              color: _colorAnimation ??= _controller.animController.drive(
                ColorTween(
                  begin: colorScheme.onInverseSurface,
                  end: colorScheme.surface,
                ).chain(CurveTween(curve: const Interval(0.8, 1.0))),
              ),
              child: child,
            ),
            );
          }
          return KeyedSubtree(
            key: ValueKey('reply-${item.id}'),
            child: child,
          );
                },
                itemCount: response.length + 1,
              )
            : SuperSliverList.builder(
                listController: _controller.listController,
                itemBuilder: (context, index) {
                  if (index == response.length) {
                    _controller.onLoadMore();
                    return Container(
                      height: 125,
                      alignment: Alignment.center,
                      margin: .only(bottom: MediaQuery.viewPaddingOf(context).bottom),
                      child: Text(
                        _controller.isEnd ? '没有更多了' : '加载中...',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.outline,
                        ),
                      ),
                    );
                  }
                  final item = response[index];
                  final reply = _replyItem(context, item, index);
                  final child = ReplyA11ySemantics(
                    replyItem: item,
                    label: _a11yLabel(item),
                    onTap: () => _controller.onReply(item, index: index),
                    onTapHint: '點兩下回覆這條評論',
                    child: reply,
                  );
                  if (jumpIndex == index) {
                    return KeyedSubtree(
                      key: ValueKey('reply-${item.id}'),
                      child: ColoredBoxTransition(
                        color: _colorAnimation ??= _controller.animController.drive(
                          ColorTween(
                            begin: colorScheme.onInverseSurface,
                            end: colorScheme.surface,
                          ).chain(CurveTween(curve: const Interval(0.8, 1.0))),
                        ),
                        child: child,
                      ),
                    );
                  }
                  return KeyedSubtree(
                    key: ValueKey('reply-${item.id}'),
                    child: child,
                  );
                },
                itemCount: response.length + 1,
              ),
      Error(:final errMsg) => HttpError(
        errMsg: errMsg,
        onReload: _controller.onReload,
      ),
    };
  }

  Widget _replyItem(BuildContext context, ReplyInfo replyItem, int index) {
    return ReplyItemGrpc(
      key: ValueKey(replyItem.id),
      replyItem: replyItem,
      replyLevel: isDialogue ? 3 : 2,
      onReply: (replyItem) => _controller.onReply(replyItem, index: index),
      onDelete: (item, subIndex) => _controller.onRemove(index, item, null),
      upMid: _controller.upMid,
      showDialogue: () => MiniScaffold.of(context).showBottomSheet(
        constraints: BoxConstraints(
          minHeight: MediaQuery.sizeOf(context).height,
          maxHeight: MediaQuery.sizeOf(context).height,
        ),
        (context) => VideoReplyReplyPanel(
          oid: replyItem.oid.toInt(),
          rpid: replyItem.root.toInt(),
          dialog: replyItem.dialog.toInt(),
          replyType: widget.replyType,
          isVideoDetail: true,
          isNested: widget.isNested,
        ),
      ),
      jumpToDialogue: () {
        if (!_controller.setIndexById(replyItem.parent)) {
          SmartDialog.showToast('评论可能已被删除');
        }
      },
      onCheckReply: (item) => _controller.onCheckReply(item, isManual: true),
    );
  }
}

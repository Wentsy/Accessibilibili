import 'package:PiliPlus/common/a11y/a11y_action_feedback.dart';
import 'package:PiliPlus/common/a11y/a11y_focus_scroll.dart';
import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart' show ReplyInfo;
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/reply.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

class ReplyA11ySemantics extends StatefulWidget {
  const ReplyA11ySemantics({
    super.key,
    required this.replyItem,
    required this.child,
    required this.label,
    this.onTap,
    this.onTapHint,
    this.onAccessibilityFocus,
  });

  final ReplyInfo replyItem;
  final Widget child;
  final String label;
  final VoidCallback? onTap;
  final String? onTapHint;
  final VoidCallback? onAccessibilityFocus;

  @override
  State<ReplyA11ySemantics> createState() => _ReplyA11ySemanticsState();
}

class _ReplyA11ySemanticsState extends State<ReplyA11ySemantics> {
  bool _didRequestReadAhead = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleVoiceOverReadAhead();
  }

  @override
  void didUpdateWidget(covariant ReplyA11ySemantics oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.replyItem.id != widget.replyItem.id) {
      _didRequestReadAhead = false;
      _scheduleVoiceOverReadAhead();
    }
  }

  void _scheduleVoiceOverReadAhead() {
    if (
      _didRequestReadAhead ||
      widget.onAccessibilityFocus == null ||
      !MediaQuery.accessibleNavigationOf(context)
    ) {
      return;
    }

    _didRequestReadAhead = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // VoiceOver Read All does not reliably move accessibility focus through
      // every lazily-built row. Treat a comment entering Flutter's viewport /
      // cache as a read-ahead signal as well. Callers already gate this to the
      // final few rows and their controllers de-duplicate in-flight requests,
      // so main comments and nested replies can preload the next API page
      // before continuous reading reaches the current semantic boundary.
      widget.onAccessibilityFocus?.call();
    });
  }

  Future<void> _toggleLike(BuildContext context) async {
    final replyItem = widget.replyItem;
    final isLiked = replyItem.replyControl.action == Int64.ONE;
    final action = isLiked ? 0 : 1;
    final res = await ReplyHttp.likeReply(
      type: replyItem.type.toInt(),
      oid: replyItem.oid.toInt(),
      rpid: replyItem.id.toInt(),
      action: action,
    );
    if (res case Success()) {
      if (isLiked) {
        replyItem
          ..like -= Int64.ONE
          ..replyControl.action = Int64.ZERO;
      } else {
        replyItem
          ..like += Int64.ONE
          ..replyControl.action = Int64.ONE;
      }
      final message = isLiked ? '已取消赞' : '点赞成功';
      SmartDialog.showToast(message);
      a11yActionFeedback(message: message);
      (context as Element).markNeedsBuild();
    } else {
      final message = isLiked ? '取消赞失败' : '点赞失败，需要登录';
      SmartDialog.showToast(message);
      a11yActionFeedback(message: message);
    }
  }

  Future<void> _toggleDislike(BuildContext context) async {
    final replyItem = widget.replyItem;
    final isDisliked = replyItem.replyControl.action == Int64.TWO;
    final action = isDisliked ? 0 : 1;
    final wasLiked = replyItem.replyControl.action == Int64.ONE;
    final res = await ReplyHttp.hateReply(
      type: replyItem.type.toInt(),
      oid: replyItem.oid.toInt(),
      rpid: replyItem.id.toInt(),
      action: action,
    );
    if (res case Success()) {
      if (!isDisliked && wasLiked) {
        replyItem.like -= Int64.ONE;
      }
      replyItem.replyControl.action = isDisliked ? Int64.ZERO : Int64.TWO;
      final message = isDisliked ? '已取消踩' : '点踩成功';
      SmartDialog.showToast(message);
      a11yActionFeedback(message: message);
      (context as Element).markNeedsBuild();
    } else {
      final message = isDisliked ? '取消踩失败' : '点赞失败，需要登录';
      SmartDialog.showToast(message);
      a11yActionFeedback(message: message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final replyItem = widget.replyItem;
    final action = replyItem.replyControl.action;
    final commentTime = DateFormatUtils.a11yDateFormat(replyItem.ctime.toInt());
    final semanticsLabel = commentTime.isEmpty
        ? widget.label
        : '${widget.label}，$commentTime評論';
    return Semantics(
      container: true,
      explicitChildNodes: false,
      label: semanticsLabel,
      hint: widget.onTapHint,
      textDirection: TextDirection.ltr,
      onTap: widget.onTap,
      onTapHint: widget.onTapHint,
      onDidGainAccessibilityFocus: () {
        widget.onAccessibilityFocus?.call();
        // Make the next lazy-list nodes available without a scroll animation
        // racing VoiceOver's read-from-current-item traversal.
        a11yEnsureVisible(context, immediate: true);
      },
      customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
        CustomSemanticsAction(
          label: action == Int64.ONE ? '取消赞' : '点赞这条评论',
        ): () => _toggleLike(context),
        CustomSemanticsAction(
          label: action == Int64.TWO ? '取消踩' : '点踩这条评论',
        ): () => _toggleDislike(context),
      },
      child: ExcludeSemantics(child: widget.child),
    );
  }
}

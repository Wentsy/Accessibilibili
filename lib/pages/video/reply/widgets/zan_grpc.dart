import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show ReplyInfo;
import 'package:PiliPlus/http/reply.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:PiliPlus/utils/num_utils.dart';
import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/semantics.dart';
import 'package:PiliPlus/common/a11y/a11y_action_feedback.dart';

import 'package:material_ui/material_ui.dart';

class ZanButtonGrpc extends StatelessWidget {
  const ZanButtonGrpc({
    super.key,
    required this.replyItem,
  });

  final ReplyInfo replyItem;

  void _announce(String message) {
    a11yActionFeedback(message: message);
  }

  Future<void> onHateReply(
    BuildContext context,
    bool isProcessing,
    VoidCallback onDone, {
    required bool isLike,
    required bool isDislike,
  }) async {
    if (isProcessing) {
      return;
    }
    isProcessing = true;
    feedBack();
    final int oid = replyItem.oid.toInt();
    final int rpid = replyItem.id.toInt();
    // 1 已点赞 2 不喜欢 0 未操作
    final int action = isDislike ? 0 : 2;
    final res = await ReplyHttp.hateReply(
      type: replyItem.type.toInt(),
      action: action == 2 ? 1 : 0,
      oid: oid,
      rpid: rpid,
    );
    if (res.isSuccess) {
      final message = isDislike ? '已取消踩' : '点踩成功';
      SmartDialog.showToast(message);
      _announce(message);
      if (action == 2) {
        if (isLike) replyItem.like -= $fixnum.Int64.ONE;
        replyItem.replyControl.action = $fixnum.Int64.TWO;
      } else {
        replyItem.replyControl.action = $fixnum.Int64.ZERO;
      }
      if (context.mounted) {
        (context as Element?)?.markNeedsBuild();
      }
    } else {
      final message = isDislike ? '取消踩失败' : '点踩失败，需要登录';
      SmartDialog.showToast(message);
      _announce(message);
      res.toast();
    }
    onDone();
  }

  // 评论点赞
  Future<void> onLikeReply(
    BuildContext context,
    bool isProcessing,
    VoidCallback onDone, {
    required bool isLike,
    required bool isDislike,
  }) async {
    if (isProcessing) {
      return;
    }
    isProcessing = true;
    feedBack();
    final int oid = replyItem.oid.toInt();
    final int rpid = replyItem.id.toInt();
    // 1 已点赞 2 不喜欢 0 未操作
    final int action = isLike ? 0 : 1;
    final res = await ReplyHttp.likeReply(
      type: replyItem.type.toInt(),
      oid: oid,
      rpid: rpid,
      action: action,
    );
    if (res.isSuccess) {
      final message = isLike ? '已取消赞' : '点赞成功';
      SmartDialog.showToast(message);
      _announce(message);
      if (action == 1) {
        replyItem
          ..like += $fixnum.Int64.ONE
          ..replyControl.action = $fixnum.Int64.ONE;
      } else {
        replyItem
          ..like -= $fixnum.Int64.ONE
          ..replyControl.action = $fixnum.Int64.ZERO;
      }
      if (context.mounted) {
        (context as Element?)?.markNeedsBuild();
      }
    } else {
      final message = isLike ? '取消赞失败' : '点赞失败，需要登录';
      SmartDialog.showToast(message);
      _announce(message);
      res.toast();
    }
    onDone();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    late bool isProcessing = false;
    final action = replyItem.replyControl.action;
    final isLike = action == $fixnum.Int64.ONE;
    final isDislike = action == $fixnum.Int64.TWO;
    final outline = theme.colorScheme.outline;
    final primary = theme.colorScheme.primary;
    final ButtonStyle style = TextButton.styleFrom(
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );

    Future<void> likeAction() => onLikeReply(
      context,
      isProcessing,
      () => isProcessing = false,
      isLike: isLike,
      isDislike: isDislike,
    );

    Future<void> hateAction() => onHateReply(
      context,
      isProcessing,
      () => isProcessing = false,
      isLike: isLike,
      isDislike: isDislike,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 32,
          child: Semantics(
            container: true,
            button: true,
            label: isDislike ? '取消踩' : '点踩',
            hint: isDislike ? '点两下取消踩' : '点两下点踩这条评论',
            onTap: hateAction,
            child: ExcludeSemantics(
              child: TextButton(
                style: const ButtonStyle(
                  visualDensity: .compact,
                  tapTargetSize: .shrinkWrap,
                  padding: WidgetStatePropertyAll(.zero),
                  minimumSize: WidgetStatePropertyAll(.square(40)),
                ),
                onPressed: hateAction,
                child: Icon(
                  isDislike
                      ? FontAwesomeIcons.solidThumbsDown
                      : FontAwesomeIcons.thumbsDown,
                  size: 16,
                  color: isDislike ? primary : outline,
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          height: 32,
          child: Semantics(
            container: true,
            button: true,
            label: isLike ? '取消赞' : '赞评论',
            hint: isLike ? '点两下取消赞这条评论' : '点两下赞这条评论',
            onTap: likeAction,
            child: ExcludeSemantics(
              child: TextButton(
                style: style,
                onPressed: likeAction,
                child: Row(
                  spacing: 4,
                  children: [
                    Icon(
                      isLike
                          ? FontAwesomeIcons.solidThumbsUp
                          : FontAwesomeIcons.thumbsUp,
                      size: 16,
                      color: isLike ? primary : outline,
                    ),
                    Text(
                      NumUtils.numFormat(replyItem.like.toInt()),
                      style: TextStyle(
                        color: isLike ? primary : outline,
                        fontSize: theme.textTheme.labelSmall!.fontSize,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:PiliPlus/common/a11y/a11y_focus_scroll.dart';
import 'package:PiliPlus/common/a11y/ios_accessibility_actions.dart';

int _nextAnchorId = 0;

/// Gives native Read All the same lazy-list progress callback as swipe focus.
class ReplyReadingAnchor extends StatefulWidget {
  const ReplyReadingAnchor({
    super.key,
    required this.identifier,
    required this.builder,
    this.onRead,
  });

  final String identifier;
  final Widget Function(String identifier) builder;
  final VoidCallback? onRead;

  @override
  State<ReplyReadingAnchor> createState() => _ReplyReadingAnchorState();
}

class _ReplyReadingAnchorState extends State<ReplyReadingAnchor> {
  final int _id = _nextAnchorId++;
  String get _identifier => '${widget.identifier}|$_id';

  @override
  void initState() {
    super.initState();
    iosReplyReadingAnchors[_identifier] = _onRead;
  }

  @override
  void didUpdateWidget(ReplyReadingAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    iosReplyReadingAnchors.remove('${oldWidget.identifier}|$_id');
    iosReplyReadingAnchors[_identifier] = _onRead;
  }

  void _onRead() {
    final position = Scrollable.maybeOf(context)?.position;
    traceReplyReading('anchorRun',
        'id=$_identifier route=${ModalRoute.of(context)?.isCurrent} '
        'pixels=${position?.pixels} max=${position?.maxScrollExtent}');
    if (!mounted || ModalRoute.of(context)?.isCurrent == false ||
        !MediaQuery.accessibleNavigationOf(context)) return;
    widget.onRead?.call();
    a11yEnsureVisible(
      context,
      immediate: true,
      recoverAfterSuppression: true,
      forwardRecovery: true,
      nearestScrollableOnly: true,
            revealFollowingReply: true,
    );
  }

  @override
  void dispose() {
    iosReplyReadingAnchors.remove(_identifier);
    cancelDeferredReplyFocus(context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_identifier);
}

import 'dart:async';
import 'dart:collection';

import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart' show ReplyInfo;
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/pages/common/reply_controller.dart';
import 'package:PiliPlus/pages/common/a11y/reply_pagination.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeReplies extends ReplyController<List<ReplyInfo>> {
  int requests = 0;
  final responses = Queue<Future<LoadingState<List<ReplyInfo>>> Function()>();
  FakeReplies() {
    loadingState.value = Success([ReplyInfo()]);
  }
  @override
  dynamic get sourceId => 1;
  @override
  bool customHandleResponse(bool refresh, Success<List<ReplyInfo>> response) => false;
  @override
  Future<LoadingState<List<ReplyInfo>>> customGetData() {
    requests++;
    return responses.removeFirst()();
  }
}

void main() {
  test('300 comments append with stable list identity; real end stops requests', () async {
    final controller = FakeReplies();
    addTearDown(controller.onClose);
    final original = controller.loadingState.value.data;
    for (var page = 0; page < 15; page++) {
      controller.responses.add(() async => Success(List.generate(20, (_) => ReplyInfo())));
      await controller.onLoadMore();
      expect(identical(original, controller.loadingState.value.data), isTrue);
    }
    expect(original!.length, 301);
    controller.responses.add(() async => const Success(<ReplyInfo>[]));
    await controller.onLoadMore();
    await controller.onLoadMore();
    expect(controller.isEnd, isTrue);
    expect(controller.requests, 16);
  });

  test('boundary request joins slow prefetch instead of completing early', () async {
    final controller = FakeReplies();
    addTearDown(controller.onClose);
    final response = Completer<LoadingState<List<ReplyInfo>>>();
    controller.responses.add(() => response.future);
    final first = controller.onLoadMore();
    final second = controller.retryLoadMore();
    expect(identical(first, second), isTrue);
    expect(controller.requests, 1);
    response.complete(Success([ReplyInfo()]));
    await second;
    expect(controller.loadingState.value.data!.length, 2);
  });

  testWidgets('failed prefetch retries once, then pauses without a retry loop', (tester) async {
    final controller = FakeReplies();
    addTearDown(controller.onClose);
    controller.responses.add(() async => const Error('offline'));
    controller.responses.add(() async => throw StateError('offline'));
    final pending = controller.onLoadMore();
    await tester.pump();
    expect(controller.requests, 1);
    await tester.pump(const Duration(milliseconds: 600));
    await pending;
    expect(controller.requests, 2);
    expect(controller.loadMoreFailed.value, isTrue);
    expect(controller.isLoading, isFalse);
    await controller.onLoadMore();
    expect(controller.requests, 2);
    controller.responses.add(() async => Success([ReplyInfo()]));
    await controller.retryLoadMore();
    expect(controller.loadingState.value.data!.length, 2);
    expect(controller.loadMoreFailed.value, isFalse);
  });

  testWidgets('refresh invalidates a queued retry', (tester) async {
    final controller = FakeReplies();
    addTearDown(controller.onClose);
    controller.responses.add(() async => const Error('offline'));
    final pending = controller.onLoadMore();
    await tester.pump();
    controller.responses.add(() async => Success([ReplyInfo()]));
    await controller.onRefresh();
    await tester.pump(const Duration(milliseconds: 600));
    await pending;
    expect(controller.requests, 2);
    expect(controller.loadMoreFailed.value, isFalse);
  });

  testWidgets('comment footer has no retry button or tap action', (tester) async {
    final controller = FakeReplies();
    addTearDown(controller.onClose);
    controller.loadMoreFailed.value = true;
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: ReplyPaginationStatus(controller: controller),
    )));
    expect(find.byType(TextButton), findsNothing);
    expect(find.text('評論暫時載入失敗'), findsOneWidget);
    expect(tester.getSemantics(find.text('評論暫時載入失敗'))
        .getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
  });

  testWidgets('short reply viewport exposes more/end and forwards the boundary', (tester) async {
    final controller = FakeReplies();
    addTearDown(controller.onClose);
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    await tester.pumpWidget(MaterialApp(home: MediaQuery(
      data: const MediaQueryData(accessibleNavigation: true),
      child: ReplyScrollView(replyController: controller, slivers: const [
        SliverToBoxAdapter(child: SizedBox(height: 100, child: Text('Comment'))),
      ]),
    )));
    Finder marker(String value) => find.byWidgetPredicate((widget) =>
        widget is Semantics && widget.properties.identifier == 'a11y-reply-scroll|$value');
    expect(marker('more'), findsOneWidget);
    controller.responses.add(() async => const Success(<ReplyInfo>[]));
    final node = tester.getSemantics(marker('more'));
    tester.binding.pipelineOwner.semanticsOwner!.performAction(node.id, SemanticsAction.scrollUp);
    await tester.pumpAndSettle();
    expect(controller.requests, 1);
    expect(marker('end'), findsOneWidget);
    final end = tester.getSemantics(marker('end'));
    tester.binding.pipelineOwner.semanticsOwner!.performAction(end.id, SemanticsAction.scrollUp);
    await tester.pumpAndSettle();
    expect(controller.requests, 1);
  });
}

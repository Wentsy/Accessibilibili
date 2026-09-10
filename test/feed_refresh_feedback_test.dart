import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/http/loading_state.dart';
import '../lib/pages/common/common_list_controller.dart';

class TestFeedController extends CommonListController<List<int>, int> {
  Future<LoadingState<List<int>>> Function() request =
      () async => const Success([1, 2]);
  bool keepOldDataOnError = false;

  @override
  Future<LoadingState<List<int>>> customGetData() => request();

  @override
  bool handleError(String? errMsg) => keepOldDataOnError;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TestFeedController controller;
  late List<String> announcements;

  setUp(() {
    controller = TestFeedController();
    announcements = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, (message) async {
      if (message is Map && message['type'] == 'announce') {
        announcements.add((message['data'] as Map)['message'] as String);
      }
      return null;
    });
  });

  tearDown(() {
    controller.scrollController.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, null);
  });

  test('refresh announces start and completion', () async {
    await controller.onA11yRefresh(label: '推薦');
    expect(announcements, ['正在重新整理推薦', '推薦重新整理完成']);
    expect(controller.loadingState.value.data, [1, 2]);
  });

  test('failed response retaining old data must not announce success', () async {
    await controller.queryData();
    controller.keepOldDataOnError = true;
    controller.request = () async => const Error('offline');
    await controller.onA11yRefresh(label: '推薦');
    expect(controller.loadingState.value.data, [1, 2]);
    expect(announcements.last, '推薦重新整理失敗，請再試一次');
    expect(controller.isLoading, isFalse);
  });

  test('thrown request unlocks the controller and a retry succeeds', () async {
    controller.request = () async => throw StateError('offline');
    await controller.onA11yRefresh();
    expect(controller.isLoading, isFalse);
    expect(announcements.last, '頁面重新整理失敗，請再試一次');
    controller.request = () async => const Success([3]);
    await controller.onA11yRefresh();
    expect(announcements.last, '頁面重新整理完成');
    expect(controller.loadingState.value.data, [3]);
  });

  test('refresh during a pending load does not reset the page', () async {
    final pending = Completer<LoadingState<List<int>>>();
    controller.request = () => pending.future;
    controller.page = 4;
    final load = controller.onLoadMore();
    await controller.onA11yRefresh();
    expect(controller.page, 4);
    expect(announcements, ['正在載入，請稍候再重新整理']);
    pending.complete(const Success([3]));
    await load;
  });

  test('automatic loads are silent; explicit end action announces no more', () async {
    await controller.queryData();
    expect(announcements, isEmpty);
    controller.isEnd = true;
    await controller.onA11yLoadMore();
    expect(announcements, ['沒有更多內容']);
  });
}

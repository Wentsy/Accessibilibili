import 'package:PiliPlus/common/a11y/a11y_action_feedback.dart';
import 'package:PiliPlus/common/a11y/a11y_focus_scroll.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/pages/common/common_controller.dart';
import 'package:get/get.dart';

abstract class CommonListController<R, T> extends CommonController<R, T> {
  int page = 1;
  bool isEnd = false;
  bool? hasFooter;
  bool _lastRequestSucceeded = false;
  bool get lastRequestSucceeded => _lastRequestSucceeded;

  /// Explicit VoiceOver feed actions only. Automatic prefetch remains silent.
  Future<void> onA11yRefresh({
    String label = '頁面',
    Future<void> Function()? refresh,
  }) async {
    if (isLoading) {
      a11yActionFeedback(message: '正在載入，請稍候再重新整理');
      return;
    }
    a11yActionFeedback(message: '正在重新整理$label');
    try {
      await (refresh ?? onRefresh)();
      a11yActionFeedback(
        message: _lastRequestSucceeded
            ? '$label重新整理完成'
            : '$label重新整理失敗，請再試一次',
      );
    } catch (_) {
      a11yActionFeedback(message: '$label重新整理失敗，請再試一次');
    }
  }

  Future<void> onA11yLoadMore() async {
    if (isLoading) {
      a11yActionFeedback(message: '正在載入，請稍候');
      return;
    }
    if (!loadingState.value.isSuccess) {
      // There is no list to append to after an initial request failed.
      await onA11yRefresh();
      return;
    }
    if (isEnd) {
      a11yActionFeedback(message: '沒有更多內容');
      return;
    }
    a11yActionFeedback(message: '正在載入更多');
    try {
      await onLoadMore();
      a11yActionFeedback(
        message: !_lastRequestSucceeded
            ? '載入失敗，請再試一次'
            : isEnd
            ? '沒有更多內容'
            : '載入完成，可以繼續向上翻頁',
      );
    } catch (_) {
      a11yActionFeedback(message: '載入失敗，請再試一次');
    }
  }

  @override
  Rx<LoadingState<List<T>?>> loadingState =
      LoadingState<List<T>?>.loading().obs;

  void handleListResponse(List<T> dataList) {}

  List<T>? getDataList(R response) {
    return response as List<T>?;
  }

  void checkIsEnd(int length) {}

  @override
  Future<void> queryData([bool isRefresh = true]) async {
    if (isLoading || (!isRefresh && isEnd)) return;
    isLoading = true;
    _lastRequestSucceeded = false;
    try {
      final LoadingState<R> res = await customGetData();
      if (res case Success(:final response)) {
        _lastRequestSucceeded = true;
        if (!customHandleResponse(isRefresh, res)) {
          final dataList = getDataList(response);
          if (dataList == null || dataList.isEmpty) {
            isEnd = true;
            if (isRefresh) {
              loadingState.value = Success(dataList);
            } else if (hasFooter == true) {
              loadingState.refresh();
            }
            return;
          }
          handleListResponse(dataList);
          if (isRefresh) {
            checkIsEnd(dataList.length);
            loadingState.value = Success(dataList);
          } else if (loadingState.value case Success(:final response)) {
            // Preserve list identity and suppress focus restoration during
            // append, so VoiceOver does not pull the viewport back to the top.
            response!.addAll(dataList);
            checkIsEnd(response.length);
            suppressA11yFocusScroll();
            loadingState.refresh();
          }
        }
        page++;
      } else {
        if (isRefresh && !handleError(res is Error ? res.errMsg : null)) {
          loadingState.value = res as Error;
        }
      }
    } finally {
      // A thrown request must not permanently disable refresh/load-more.
      isLoading = false;
    }
  }

  @override
  Future<void> onRefresh() {
    page = 1;
    isEnd = false;
    return super.onRefresh();
  }

  @override
  Future<void> onReload() {
    loadingState.value = LoadingState<List<T>?>.loading();
    return super.onReload();
  }
}

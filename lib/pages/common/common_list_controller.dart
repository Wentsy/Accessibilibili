import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/pages/common/common_controller.dart';
import 'package:get/get.dart';

abstract class CommonListController<R, T> extends CommonController<R, T> {
  int page = 1;
  bool isEnd = false;
  bool? hasFooter;

  @override
  Rx<LoadingState<List<T>?>> loadingState =
      LoadingState<List<T>?>.loading().obs;

  /// VoiceOver 的左右滑動/三指翻頁可能一次跨越一個 viewport，
  /// 不能等到 SliverList 真正建立最後一個 child 才載入下一頁。
  /// 在接近尾端時提前預取，讓下一批資料在焦點抵達前就進入語義樹。
  static const double _a11yPrefetchMultiplier = 1.5;
  static const double _a11yPrefetchMinimum = 480;

  @override
  void onInit() {
    super.onInit();
    scrollController.addListener(_onA11yScroll);
  }

  void _onA11yScroll() {
    if (isLoading || isEnd || !scrollController.hasClients) return;

    final position = scrollController.position;
    final remaining = position.maxScrollExtent - position.pixels;
    final threshold = (position.viewportDimension * _a11yPrefetchMultiplier)
        .clamp(_a11yPrefetchMinimum, double.infinity);

    if (remaining <= threshold) {
      onLoadMore();
    }
  }

  void handleListResponse(List<T> dataList) {}

  List<T>? getDataList(R response) {
    return response as List<T>?;
  }

  void checkIsEnd(int length) {}

  @override
  Future<void> queryData([bool isRefresh = true]) async {
    if (isLoading || (!isRefresh && isEnd)) return;
    isLoading = true;
    final LoadingState<R> res = await customGetData();
    if (res case Success(:final response)) {
      if (!customHandleResponse(isRefresh, res)) {
        final dataList = getDataList(response);
        if (dataList == null || dataList.isEmpty) {
          isEnd = true;
          if (isRefresh) {
            loadingState.value = Success(dataList);
          } else if (hasFooter == true) {
            loadingState.refresh();
          }
          isLoading = false;
          return;
        }
        handleListResponse(dataList);
        if (isRefresh) {
          checkIsEnd(dataList.length);
          loadingState.value = Success(dataList);
        } else if (loadingState.value case Success(:final response)) {
          response!.addAll(dataList);
          checkIsEnd(response.length);
          loadingState.value = Success(response); // a11y fix: direct assign avoids SliverList rebuild
        }
      }
      page++;
    } else {
      if (isRefresh && !handleError(res is Error ? res.errMsg : null)) {
        loadingState.value = res as Error;
      }
    }
    isLoading = false;
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

  @override
  void onClose() {
    scrollController.removeListener(_onA11yScroll);
    super.onClose();
  }
}

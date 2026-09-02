import 'package:PiliPlus/common/a11y/a11y_action_feedback.dart';
import 'package:PiliPlus/http/fav.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models_new/sub/sub/list.dart';
import 'package:PiliPlus/models_new/sub/sub_detail/data.dart';
import 'package:PiliPlus/models_new/sub/sub_detail/media.dart';
import 'package:PiliPlus/pages/common/common_list_controller.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:get/get.dart';

class SubDetailController
    extends CommonListController<SubDetailData, SubDetailItemModel> {
  late int id;
  String? heroTag;
  SubItemModel? subInfo;

  final newestFirst = true.obs;
  bool _loadingAll = false;

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments;
    id = args['id'];
    subInfo = args['subInfo'];
    heroTag = args['heroTag'];

    _loadAllVideos();
  }

  int _sortTime(SubDetailItemModel item) => item.pubtime ?? 0;

  void _sortItems(List<SubDetailItemModel> items) {
    items.sort((a, b) {
      final aTime = _sortTime(a);
      final bTime = _sortTime(b);
      final timeCompare = newestFirst.value
          ? bTime.compareTo(aTime)
          : aTime.compareTo(bTime);
      if (timeCompare != 0) return timeCompare;
      return (a.id ?? 0).compareTo(b.id ?? 0);
    });
  }

  Future<void> _loadAllVideos() async {
    if (_loadingAll) return;
    _loadingAll = true;

    final items = <SubDetailItemModel>[];
    var currentPage = 1;
    const pageSize = 20;

    while (true) {
      final res = await FavHttp.favSeasonList(
        id: id,
        ps: pageSize,
        pn: currentPage,
      );
      if (res case Success(:final response)) {
        subInfo = response.info ?? subInfo;
        final batch = response.medias ?? const <SubDetailItemModel>[];
        items.addAll(batch);

        final total = subInfo?.mediaCount;
        if (batch.isEmpty ||
            batch.length < pageSize ||
            (total != null && items.length >= total)) {
          break;
        }
        currentPage++;
      } else if (res case Error(:final errMsg, :final code)) {
        loadingState.value = Error(errMsg, code: code);
        _loadingAll = false;
        return;
      }
    }

    _sortItems(items);
    loadingState.value = Success(items);
    page = currentPage + 1;
    isEnd = true;
    _loadingAll = false;
  }

  Future<void> toggleSort() async {
    newestFirst.value = !newestFirst.value;
    if (loadingState.value case Success(:final response)) {
      if (response != null) {
        _sortItems(response);
        loadingState.refresh();
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollController.hasClients) {
        scrollController.jumpTo(scrollController.position.minScrollExtent);
      }
      a11yActionFeedback(
        message: newestFirst.value ? '合集影片已切換為最新優先' : '合集影片已切換為最舊優先',
      );
    });
  }

  @override
  Future<void> onRefresh() async {
    page = 1;
    isEnd = false;
    await _loadAllVideos();
  }

  @override
  List<SubDetailItemModel>? getDataList(SubDetailData response) {
    subInfo = response.info;
    return response.medias;
  }

  @override
  void checkIsEnd(int length) {
    final count = subInfo?.mediaCount;
    if (count != null && length >= count) {
      isEnd = true;
    }
  }

  @override
  Future<LoadingState<SubDetailData>> customGetData() => FavHttp.favSeasonList(
    id: id,
    ps: 20,
    pn: page,
  );
}

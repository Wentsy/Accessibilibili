import 'package:PiliPlus/common/a11y/a11y_action_feedback.dart';
import 'package:PiliPlus/http/fav.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/user.dart';
import 'package:PiliPlus/models_new/sub/sub/data.dart';
import 'package:PiliPlus/models_new/sub/sub/list.dart';
import 'package:PiliPlus/pages/common/common_list_controller.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class SubController extends CommonListController<SubData, SubItemModel> {
  late final account = Accounts.main;
  final newestFirst = true.obs;

  bool _sortedModeActive = false;
  bool _sorting = false;

  @override
  void onInit() {
    super.onInit();
    queryData();
  }

  @override
  Future<void> queryData([bool isRefresh = true]) {
    if (!account.isLogin) {
      loadingState.value = const Error('账号未登录');
      return Future.syncValue(null);
    }
    return super.queryData(isRefresh);
  }

  int _sortTime(SubItemModel item) => item.mtime ?? item.ctime ?? 0;

  void _sortItems(List<SubItemModel> items) {
    items.sort((a, b) {
      final aTime = _sortTime(a);
      final bTime = _sortTime(b);
      return newestFirst.value
          ? bTime.compareTo(aTime)
          : aTime.compareTo(bTime);
    });
  }

  Future<bool> _loadAllSubscriptions() async {
    if (_sorting) return false;
    _sorting = true;

    final items = <SubItemModel>[];
    var currentPage = 1;

    while (true) {
      final res = await UserHttp.userSubFolder(
        pn: currentPage,
        ps: 70,
        mid: account.mid,
      );
      if (res case Success(:final response)) {
        items.addAll(response.list ?? const <SubItemModel>[]);
        if (response.hasMore != true) {
          break;
        }
        currentPage++;
      } else {
        res.toast();
        _sorting = false;
        return false;
      }
    }

    _sortItems(items);
    loadingState.value = Success(items);
    page = currentPage + 1;
    isEnd = true;
    _sorting = false;
    return true;
  }

  Future<void> toggleSort() async {
    final previous = newestFirst.value;
    newestFirst.value = !previous;
    _sortedModeActive = true;

    if (await _loadAllSubscriptions()) {
      a11yActionFeedback(
        message: newestFirst.value ? '已切換為最新優先' : '已切換為最舊優先',
      );
    } else {
      newestFirst.value = previous;
    }
  }

  @override
  Future<void> onRefresh() async {
    if (_sortedModeActive) {
      await _loadAllSubscriptions();
      return;
    }
    await super.onRefresh();
  }

  // 取消订阅
  void cancelSub(SubItemModel subFolderItem) {
    showDialog(
      context: Get.context!,
      builder: (context) => AlertDialog(
        title: const Text('提示'),
        content: const Text('确定取消订阅吗？'),
        actions: [
          TextButton(
            onPressed: Get.back,
            child: Text(
              '取消',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          TextButton(
            onPressed: () async {
              final res = await FavHttp.cancelSub(
                id: subFolderItem.id!,
                type: subFolderItem.type!,
              );
              if (res.isSuccess) {
                loadingState
                  ..value.data!.remove(subFolderItem)
                  ..refresh();
                SmartDialog.showToast('取消订阅成功');
              } else {
                res.toast();
              }
              Get.back();
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  List<SubItemModel>? getDataList(SubData response) {
    if (response.hasMore == false) {
      isEnd = true;
    }
    return response.list;
  }

  @override
  Future<LoadingState<SubData>> customGetData() => UserHttp.userSubFolder(
    pn: page,
    ps: 20,
    mid: account.mid,
  );
}

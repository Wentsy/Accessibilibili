import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/pages/common/common_list_controller.dart';
import 'package:PiliPlus/utils/storage_pref.dart';

class RcmdController extends CommonListController {
  late bool enableSaveLastData = Pref.enableSaveLastData;
  final bool appRcmd = Pref.appRcmd;

  int? lastRefreshAt;
  late bool savedRcmdTip = Pref.savedRcmdTip;

  @override
  bool get isEnd => false;

  @override
  void onInit() {
    super.onInit();
    page = 0;
    queryData();
  }

  @override
  Future<LoadingState> customGetData() {
    return appRcmd
        ? VideoHttp.rcmdVideoListApp(freshIdx: page)
        : VideoHttp.rcmdVideoList(freshIdx: page, ps: 20);
  }

  @override
  bool handleError(String? errMsg) {
    return enableSaveLastData;
  }

  Object? _videoIdentity(dynamic item) {
    try {
      return item.bvid ?? item.aid;
    } catch (_) {
      return null;
    }
  }

  @override
  void handleListResponse(List dataList) {
    // Recommendation APIs may return overlapping batches. Re-adding the same
    // semantic nodes makes VoiceOver appear to loop on the same videos.
    if (page > 0) {
      if (loadingState.value case Success(:final response)) {
        final seen = <Object?>{};
        if (response != null) {
          for (final item in response) {
            seen.add(_videoIdentity(item));
          }
        }
        dataList.removeWhere((item) {
          final id = _videoIdentity(item);
          return id != null && !seen.add(id);
        });
      }
    }

    if (enableSaveLastData && page == 0) {
      if (loadingState.value case Success(:final response)) {
        if (response != null && response.isNotEmpty) {
          if (savedRcmdTip) {
            lastRefreshAt = dataList.length;
          }
          if (response.length > 200) {
            dataList.addAll(response.take(50));
          } else {
            dataList.addAll(response);
          }
        }
      }
    }
  }

  @override
  Future<void> onRefresh() {
    page = 0;
    isEnd = false;
    return queryData();
  }
}

import 'dart:async';

import 'package:PiliPlus/common/a11y/a11y_focus_scroll.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models/home/rcmd/result.dart';
import 'package:PiliPlus/pages/common/common_list_controller.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/widgets.dart';

class RcmdController extends CommonListController {
  late bool enableSaveLastData = Pref.enableSaveLastData;
  final bool appRcmd = Pref.appRcmd;

  static final Map<String, int> _appPubdateCache = <String, int>{};
  static final Set<String> _appPubdateAttempted = <String>{};
  bool _isHydratingAppPubdates = false;
  bool _hydrateAgain = false;

  int? lastRefreshAt;
  late bool savedRcmdTip = Pref.savedRcmdTip;

  @override
  bool get isEnd => false;

  bool get _accessibilityNavigationEnabled => WidgetsBinding
      .instance
      .platformDispatcher
      .accessibilityFeatures
      .accessibleNavigation;

  @override
  void onInit() {
    super.onInit();
    page = 0;
    queryData();
  }

  @override
  Future<void> queryData([bool isRefresh = true]) async {
    await super.queryData(isRefresh);
    if (appRcmd && _accessibilityNavigationEnabled) {
      unawaited(_hydrateAppPubdates());
    }
  }

  Future<void> _hydrateAppPubdates() async {
    if (_isHydratingAppPubdates) {
      _hydrateAgain = true;
      return;
    }

    List<RcmdVideoItemAppModel> items;
    if (loadingState.value case Success(:final response)) {
      if (response == null || response.isEmpty) return;
      items = response.whereType<RcmdVideoItemAppModel>().toList();
    } else {
      return;
    }

    bool changed = false;
    final pending = <RcmdVideoItemAppModel>[];
    for (final item in items) {
      final bvid = item.bvid;
      if (bvid == null || bvid.isEmpty || (item.pubdate ?? 0) > 0) continue;

      final cached = _appPubdateCache[bvid];
      if (cached != null) {
        item.pubdate = cached;
        changed = true;
      } else if (_appPubdateAttempted.add(bvid)) {
        pending.add(item);
      }
    }

    if (pending.isEmpty) {
      if (changed) {
        suppressA11yFocusScroll();
        loadingState.refresh();
      }
      return;
    }

    _isHydratingAppPubdates = true;
    try {
      // The app recommendation feed does not expose pubdate. Hydrate it in
      // small background batches so the first recommendation render never
      // waits for per-video detail requests.
      const batchSize = 3;
      for (var start = 0; start < pending.length; start += batchSize) {
        final end = (start + batchSize).clamp(0, pending.length);
        final batch = pending.sublist(start, end);
        final results = await Future.wait(
          batch.map((item) async {
            final bvid = item.bvid!;
            try {
              final res = await VideoHttp.videoIntro(bvid: bvid);
              if (res case Success(:final response)) {
                final pubdate = response.pubdate;
                if (pubdate != null && pubdate > 0) {
                  _appPubdateCache[bvid] = pubdate;
                  item.pubdate = pubdate;
                  return true;
                }
              }
            } catch (_) {
              // Publish time is optional metadata; recommendation loading must
              // stay usable even if a detail request fails.
            }
            return false;
          }),
        );
        if (results.any((value) => value)) changed = true;
      }
    } finally {
      _isHydratingAppPubdates = false;
    }

    if (changed) {
      // Keep the current semantic/list identity stable while making the newly
      // hydrated time available to already-built cards.
      suppressA11yFocusScroll();
      loadingState.refresh();
    }

    if (_hydrateAgain) {
      _hydrateAgain = false;
      unawaited(_hydrateAppPubdates());
    }
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

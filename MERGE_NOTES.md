# 上游同步進度（PiliPlus 2.1.6.2 / main 到 2026-10-22）

本地工作 repo：`C:\Users\wents\Documents\Accessibilibili`
分支：`main`
merge-base：`35e5454a4`（自家 `cfcf25943` = 2.1.3+5737）
上游：`006c0fdd1`
衝突：53 個，全部解完，工作樹無殘留標記。

## 解法原則
- 純 import 衝突 → 兩邊 union。
- 四情境核心（影片留言 `reply/view.dart`、樓中樓 `reply_reply/view.dart`、
  簡介 `introduction/ugc/*`、`common/reply_controller.dart`、`reply_item_grpc`、
  `zan_grpc`）→ 以自家 a11y 為底，逐一接上上游新 API（色塊動畫、分頁狀態、
  節流搬進 controller、`rootRpId` 回到 ReplyController）。
- 相簿匯出（PhotoExport）客製功能完整保留：`download_service.dart` 沿用自家版本，
  但把上游新增的 `index / audioQuality / seasonInfo` 具名參數與 `updateSegments`
  補回來，呼叫端同步改成具名引數。
- 上游整個重寫、且與四情境無關的畫面先取上游：`header_control`、`main_reply`、
  `common_dyn_page`、`chat_panel`、`live_room/send_danmaku`、`reply_new`、
  `history/item`、`http/download`、`download_panel`。這些畫面的 a11y 包裝待補。
- 已在 2.1.6+6024 補回自家 a11y：`chat_panel`（直播彈幕合併語義）、
  `live_room/send_danmaku`（原生編輯器＋清除鍵朗讀）、
  `reply_new`（原生編輯器＋公式／轉到動態選取朗讀）、
  `history/item`（整條合併＋上滑動作）。
- `common_dyn_page` 取上游後，補回 `dockComposer / composerDock / composerFooter`
  （article、dynamics_detail、music、match_info 都要用）。
- AppDelegate：上游 PipPlugin 註冊 + 自家整段 a11y / textLinkRotor / exporter 初始化。
- pubspec：version 取上游 `2.1.6`（build code 由 CI 用 commit 數產生）；
  `media_kit_libs_ios_video` 保留本地 `packages/` 路徑。

## 編譯驗證方式（重要）
`lib/scripts/patch.ps1` 會 patch **Flutter SDK 本體**與 pub cache 的
`material_ui` / `cupertino_ui`。本機要先跑：

```powershell
$env:FLUTTER_ROOT='C:\Users\wents\AppData\Local\flutter_sdk'
$env:GITHUB_WORKSPACE=(Get-Location).Path
.\lib\scripts\patch.ps1 ios      # 注意：它內部的 ~/.pub-cache 在 Windows 會失敗
```

Windows 上 patch.ps1 走到 pub cache 段會找不到 `~/.pub-cache`，
要手動對 `%LOCALAPPDATA%\Pub\Cache\hosted\pub.dev\material_ui-1.8.0`
（以及 `cupertino_ui-1.1.4`）套 `lib/scripts/material`、`lib/scripts/cupertino` 的 patch。
套完 patch 後 `flutter analyze` 才是可信的（否則會誤報一堆
`DraggableScrollableSheetState`、`TabBarView.horizontalDragGestureRecognizer` 之類）。

套完 patch 後：`flutter analyze` → **0 error**。

## 注意
- `patch.ps1` 會在 repo 內套 `bottom_sheet_ios_piliplus.patch`、
  `geetest_ios.patch`（改 `mini_scaffold.dart`、`common_slide_page.dart`、
  `geetest_webview_dialog.dart`，新增 `geetest_plugin.dart`、pubspec 加
  `gt3_flutter_plugin`）。**這些不能 commit**，CI 會自己套。
- 舊穩定 `2.1.3+5737` 與其 IPA 完全沒動。
- 穩定基準要等希希 iPhone 實機測過四情境才更新 `docs/CURRENT_ACCESSIBILITY_BASELINE.md`。

## 待辦
1. CI 編譯出 IPA → 給希希實機測四情境（外層評論／展開簡介／摺疊簡介／樓中樓）。
2. 補回先取上游那些畫面的 a11y 包裝：header_control（播放器控制）、main_reply、
   common_dyn_page（動態留言）、chat_panel / live_room send_danmaku（直播）、
   reply_new（發評論）、history/item、download_panel。

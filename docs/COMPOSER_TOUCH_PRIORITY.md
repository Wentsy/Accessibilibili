# Composer 觸摸優先與樓中樓後續修正

## iOS VoiceOver 樓中樓標頭隨內容捲動（待實機驗證）

使用者回報 `5b69d333fe8521862820c3186311ebe30f616605` 仍會在單指左滑回翻時
插入統計／排序，順向正常。沒有取得原生日誌，不能斷言 `.previous` 沒被呼叫，
但該版的局部續接並未解決實際症狀。

本次撤回該版延遲追焦與診斷日誌，`SceneDelegate.swift` 回到已驗證觸摸按鈕
可用的 `d720c09` 內容。穿牆隔離、排序鍵、前向 Read All 均保留。

只在原生 iOS 且 `MediaQuery.accessibleNavigationOf(context)` 開啟時，樓中樓
統計／排序列使用 `SliverToBoxAdapter`，隨列表內容捲動；其餘情況沿用
`SliverPinnedHeader`。此方案會改變 VoiceOver 模式的吸頂效果，讓標頭不再
於每一頁頂端持續可見。標頭與按鈕仍在原本的邏輯位置，回到頂部可操作；
沒有刪除、永久排到末尾或偽造無障礙命中框。

驗收：向下瀏覽數頁後單指左滑回翻，應依回覆順序持續回到前文；回到列表
頂部後仍能找到統計及按時間／按熱度，切換有效。複驗順向單指、Read All、
沒有更多之後不穿牆、觸摸發表按鈕；關閉 VoiceOver 後排序列仍吸頂。

本環境無 Flutter/iOS SDK，未編譯或實機驗證。已檢查 diff 及比對原生橋接
與 d720c09 完全一致，穿牆相關程式未更動。

## Backward 閱讀鏈續接（歷史嘗試，未解決，已撤回）

使用者確認 `d720c09f55a421d25d996781cae978d607ddfe87` 已解決底部穿牆，
但回翻時統計／排序仍插隊。本次完整保留該版 Dart 隔離與排序、composer bridge
及 forward page-turn，只修改閱讀鏈 `.previous` 成功捲動後的完成處理。

記錄翻頁前評論 identifier 與原 viewport；等待 120ms，再於同一 viewport 的
最新語意樹尋找原評論及前一則。僅在 viewport 已往回捲、前一則可見、
焦點仍屬原評論時，以 `layoutChanged(previous)` 續接，不發無目標的
`pageScrolled(nil)`。語意未就緒最多再等四次 40ms；找不到目標則沿用原通知。
新閱讀鏈捲動、焦點離開或 viewport 移除時取消，不追焦、不搜尋其他面板。

尚不能證明單指左滑一定經過此閱讀鏈入口；Flutter 的 swipe-to-focus /
showOnScreen 也會捲動畫面。Sol 提出的原因目前是待驗證假設，不是已確認根因。
保留 `[ReplyBackward]` 原生日誌（不含評論內容或 identifier）：

- `page request`：確實收到閱讀鏈往回翻頁。
- `resumed at preceding reply`：找到目標並送出定向通知。
- `cancelled`：焦點／viewport 已改變，取消延遲動作。
- `fallback`：等待後仍無可見前一則，使用原完成通知。

若插隊時完全沒有 `page request`，下一步應查普通 swipe-to-focus 捲動路徑，
不要擴大此補丁到全域焦點操作。若有 resumed 仍插隊，需再驗證 UIKit 是否採用
通知目標。Hermes 可用 macOS Console 收集手機日誌並搜尋 `[ReplyBackward]`。

此環境無 iOS SDK／手機，未編譯或實機驗證；已檢查 diff，並以程式比對
composer bridge、forward handler、原通知函式及全部 Dart 檔均未改變。
實機請測反向連續跨頁、不跳過／重複回覆，並複驗前向 Read All、按鈕觸摸、
底部不穿牆，以及回翻後立刻關閉面板時不會把焦點拉回。

使用者已回報 `3e5095f75075ffc0be5e00a41e63204cb860d6b1` 的觸摸優先修正
完全實測通過。以下保留該次修改紀錄；新的待驗證項目是樓中樓底部穿到
外層評論，以及反向瀏覽時吸頂標頭插入評論之間。

## 樓中樓後續修正（待實機驗證）

- 評論／對話使用 MiniScaffold 浮層時，明確啟用 `excludeBodySemantics`。
  浮層顯示至退場完成期間排除底層語意；底層 widget 繼續掛載，關閉後恢復語意。
  此選項預設關閉，其他浮層不改變原有行為。涵蓋影片評論、動態橫向浮層、
  樓中樓再開對話；獨立 route 沿用既有路由隔離。
- 樓中樓明確排序：主評論 0、吸頂統計／排序群組 1、回覆從 2 開始、結尾最後。
  不移動視覺位置，不移除排序按鈕，不操作原生焦點。
- `SceneDelegate.swift` 與已實測通過的觸摸修正版完全一致。
- 新增 `test/comment_sheet_semantics_test.dart`，涵蓋預設浮層、背景隔離、
  關閉恢復且不重新掛載，以及第二層對話隔離。此環境沒有 Flutter SDK，未執行。

手機重點：樓中樓到底後連續右滑，不得進入外層評論；左滑往回跨至少兩頁，
統計／排序不得插在兩則回覆之間；關閉樓中樓後可繼續瀏覽外層。
另複驗樓中樓再開對話、Read All 自動翻頁、觸摸發表按鈕與編輯器開關。

穩定基準：`7caffb10e712f66ccfdfd99c23fbd6569801db0a`。
該基準的影片外層、樓中樓、動態評論 Read All 自動翻頁，以及普通左右滑，已由使用者驗證。

## 本次修改

基準的 direct-touch bridge 能摸到外層發表評論，但列表仍可翻頁時，
上下觸摸翻頁區會搶走觸摸。本次優先驗證原生 hit-test 入口，沒有移動按鈕。

Flutter 3.47.1 的 `FlutterSemanticsScrollView` 是原生 `UIScrollView`，
加入 FlutterView 作為 subview；它的 accessibility hit-test 與背後的
`SemanticsObject` 不同。`5fed154b` 修改的是後者，本次在前者新增 class-local
override，保留原本 UIKit implementation 作為 fallback。

新路徑僅在 VoiceOver 開啟、原生垂直可捲動 viewport 包含已標記評論，
且觸摸位於 viewport 及已標記 composer 的實際 accessibilityFrame 內時回傳
現有 composer proxy。其他位置交回原處理。
沒有修改 scroll frame、content size、捲動 action、Read All bridge、
container enumeration 或 focus callback。

樓中樓僅在原生 iOS 額外顯示既有位置的浮動回覆按鈕，加入明確的
`a11y-touch-only|publish-reply` 標記，套用相同 touch-only bridge。
列表末尾的原有回覆按鈕保留。其他平台沿用原先顯示條件。

原始碼依據：
https://github.com/flutter/flutter/blob/3.47.1/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterSemanticsScrollView.mm
https://github.com/flutter/flutter/blob/3.47.1/engine/src/flutter/shell/platform/darwin/ios/framework/Source/SemanticsObject.mm

## Hermes 編譯與手機驗收

此環境沒有 Flutter、Swift/UIKit SDK 或 iPhone，尚未完成 iOS 編譯與實機驗證。
已檢查差異空白錯誤，並確認 Read All bridge 和 scene lifecycle 與基準逐字一致。
原生 UIKit 是否在觸摸翻頁區採用此入口仍屬待驗證假設，不能視為已修好。

1. 影片外層評論停在第一頁，確認仍有很多評論可翻頁；觸摸發表評論的原位置，
   應朗讀按鈕且雙擊打開正確編輯器。關閉後，在列表中段重試。
2. 樓中樓、動態評論重複同一測試；確認回覆目標正確。
3. 同一位置稍微離開按鈕框，原有觸摸翻頁應仍可用；三指翻頁應正常。
4. 三種評論列表各用雙指下滑讀過至少兩次自動翻頁，再以普通左右滑跨頁；
   不應撞牆、跳回開頭或多出浮動 composer 的線性焦點。
5. 列表到底、空列表、關閉樓中樓、開啟編輯器及其他遮罩時，檢查沒有摸到背景按鈕。
6. 首頁、動態列表、我的頁面各檢查普通左右滑與觸摸探索；VoiceOver 關閉後正常操作。

若第一項仍被翻頁區攔住，先記錄 iOS 版本、觸摸位置與當時翻頁方向，
不要重做全域 SemanticsObjectContainer traversal/filter、
accessibilityElementAtIndex 捲動或全域 focus 移動。
本分支尚未改用視覺位移 fallback。

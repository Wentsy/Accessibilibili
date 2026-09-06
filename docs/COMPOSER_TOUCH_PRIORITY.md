# Composer 觸摸優先：待實機驗證

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

# 固定底部評論／回覆入口（待實機驗證）

穩定對照：`b2cefb20ed11c2489365b3304d298f17bcc033dc`。
本次依使用者觀察，讓發表入口比照首頁底部標籤的位置，在列表翻頁區下方獨立布局。
這是新布局測試，尚不可取代 `ACCESSIBILITY_MAINTENANCE.md` 中已實測的行為基準。

## 布局與觸摸契約

- 僅在原生 iOS 且 accessible navigation 開啟時啟用。
- 共用 `lib/common/a11y/composer_dock.dart`：底部單一大按鈕，至少高 56 logical pixels、
  水平留白 12，加上下留白與 SafeArea；顯示「發表評論」或「發表回覆」。
- `SimpleScaffold`／`ScaffoldLayout.bottomBar` 將 footer 放在 Column 中，
  列表只使用剩餘高度。因此是實際縮小 scroll viewport，不是蓋在列表上或
  只在列表結尾多加 padding。發表列不加入 FAB 的滾動隱藏動畫。
- 沿用 `a11y-touch-only|publish-comment`／`a11y-touch-only|publish-reply`，
  由既有原生 composer bridge 排除線性遍歷，只在實際 frame 內供觸摸探索。
  Swift Read All、觸摸橋接及上下翻頁行為未修改。
- iOS VoiceOver 模式下移除舊浮動 composer 與樓中樓末尾的重複發表按鈕。
  回覆個別評論的原操作保留；固定回覆入口仍回覆目前 thread 根評論。

## 套用範圍

| 入口 | 處理 |
| --- | --- |
| 影片外層評論 | Viewport 下方固定發表評論 |
| 樓中樓／對話 | MiniScaffold 的 body 內固定發表回覆，使再開對話時底層連同 dock 一起隔離 |
| 動態詳情、專欄、音樂 | 保留原有分享／讚等操作，排列於固定 composer 上方，不與它重疊 |
| 賽事詳情 | 固定發表評論 |
| 獨立「查看評論」頁 | 固定發表評論，使用相同原生標記 |

橫向動態類頁面的樓中樓在此模式下沿用既有完整詳情 route，而不是只覆蓋
評論半邊的 inline sheet，避免全頁 footer 留在新 thread 下方仍可觸摸。
其他平台與非 VoiceOver 顯示條件沿用原先方式。

## 驗收

已新增 `test/composer_dock_test.dart`，覆蓋直向／橫向按鈕框與 viewport 不重疊、
底部安全區、捲動後位置固定、點擊 callback、bridge identifier 與平台開關。
此環境沒有 Flutter／iOS SDK，未執行 widget tests、編譯或手機測試。

Hermes 編譯前可執行 `flutter test test/composer_dock_test.dart`。
Flutter widget test 不含 iOS native bridge，以下一定要手機驗收：

1. 上述每種頁面在第一頁及中間頁均能摸到下方發表入口，雙擊開啟正確目標。
2. 單指左右滑、Read All 均略過固定發表列；連讀跨至少兩頁仍正常。
3. 在發表列上方的列表區仍可觸摸快速翻頁與三指翻頁。
4. 開啟樓中樓／再開對話／編輯器時，摸不到後方舊發表入口；關閉後恢復。
5. 樓中樓到底不穿牆，回滑不插入統計／排序，回到頂部仍可操作排序。
6. 橫豎切換、小螢幕、較大文字、鍵盤開關、底部安全區均不遮住按鈕。
7. VoiceOver 關閉後，原本浮動按鈕及其他操作列行為正常。

# 大量評論連續閱讀恢復：待 Hermes 編譯及 iPhone 實測

## 後續編譯修正（2026-09-11）

使用者轉述 Hermes 已完成 +5669 編譯：`a2f7b64`
（`fix/reply-pagination-const`）明確匯入 `OrdinalSortKey` 並去除該行
const，沒有更動分頁邏輯。原版 `84d046b` 並非可編譯版本；下文
的語法解析結果不能視為 Dart 編譯驗證。長評論串 VoiceOver 實測
仍待使用者確認，尚不更新穩定基準。

## 本次範圍

- 影片／番劇主評論、一般「查看評論」頁。
- 動態、文章／圖文、音樂、賽事的共用評論區；直向與橫向評論 viewport。
- 樓中樓與對話列表，包含從上述入口開啟的回覆。
- 沒有新增重試按鈕、tap action、定時朗讀或強制重新開始 Read All。
- 不改首頁、動態首頁及觀看紀錄的三指刷新方向；不改播放器音訊。

## 修復

1. ReplyController 共用同一個進行中的分頁 Future；原生閱讀遇到
   載入邊界時會等待它，不再因 isLoading 直接完成接續請求。
2. 分頁失敗／例外後等待 600 ms 自動重試一次，保留舊評論。
   仍失敗則顯示純文字狀態，停止背景重試避免無限請求。
   閱讀再次進入尾端評論、狀態文字或發出邊界翻頁時可重新請求，
   不需按重試按鈕。持續斷網時不能保證不停讀。
3. 分頁追加的 500 ms 焦點捲動抑制保留；評論焦點仍在時，補做
   被抑制的捲動。失去焦點取消；舊節點在 viewport 上方時不回跳。
4. 原生最後一則評論的 causesPageTurn 同時檢查 Dart 的 more/end
   標記。已載入內容的暫時底部可以請求下一頁，真正結尾不再請求。
   短於一屏的原生捲動容器也可辨識。新資料完成 layout 後才通知
   pageScrolled；一般背景預載不發送公告。
5. 一般評論頁不再用評論數作為整份 SliverList 的 key；改用每則
   評論的穩定 key 和索引查找，接入共用閱讀語義與倒數五則預載。

原生映射注意：Flutter UIKit 的 `.up` 對應 `SemanticsAction.scrollDown`，
`.down` 對應 `scrollUp`。原生內層正常向前捲動沿用 `.up`；呼叫本專案
外層 wrapper 的向前 action 時使用 `.down`，不可交換。

## 已執行與限制

- 修改的 Dart 檔與新增測試通過 tree-sitter 語法解析；git diff --check。
- Swift 語法解析與 main 對比無新增錯誤；解析器對既有 feedWrapper
  的 `as? NSObject ?? receiver` 有相同的兩個誤報，不能當作 Swift 編譯。
- 此環境沒有 Dart、Flutter、Swift／Xcode SDK，未執行 Flutter tests、
  Dart analyzer 或 IPA 編譯。以下測試是待執行項目，非已通過宣告。
- 目前穩定無障礙基準未更新。

## Hermes

拉取 main 後沿用專案現有 Flutter SDK、依賴及 IPA 編譯流程。先執行：

```sh
flutter test test/reply_pagination_test.dart test/a11y_focus_scroll_test.dart test/voiceover_feed_scroll_test.dart test/comment_sheet_semantics_test.dart test/composer_dock_test.dart
```

新測試涵蓋 300 則以上追加／列表身份、慢請求合併、失敗有限重試、
刷新取消待重試、無重試按鈕、短清單 more/end、抑制後恢復與防跳頂。

## iPhone 驗收

每類評論入口選擇數百則評論，雙指下滑連續閱讀，跨多次資料分頁；
特別確認停住的位置繼續右滑可接續，不必先往左退。

再測短暫斷網後恢復、持續斷網、最後一頁、樓中樓返回、排序、
直橫向切換，以及手動停止朗讀／離開頁面後不突然重新說話。
檢查不跳回第一則、不漏下一則、發表評論／回覆仍固定可觸摸。
三指向下往回翻，三指向上翻下一頁，方向維持既有基準。

實機結果由使用者確認後，才更新 CURRENT_ACCESSIBILITY_BASELINE.md。

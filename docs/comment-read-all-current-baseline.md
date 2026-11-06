# 評論 VoiceOver 連續朗讀：現行穩定基準

## 2026-11-07：動態評論與圖文評論穩定基準

- 希希回報本次修復測試完成，沒有問題；功能提交 `7039c1e8e864891cfa29ac2577e498017c3a3f7b` 作為新的穩定程式碼基準。
- 國際版帳號的圖文評論，在已有圖片資料時移除多餘的升級提示，保留評論內容與圖片標示。
- 動態詳細頁的 VoiceOver 評論沿用影片評論的預載、穩定閱讀節點與焦點捲動機制，改善左右滑動接續下一頁。同步上游時請保留 [實作細節](dynamic-comment-reading-handoff.md)。
- 本次確認範圍為上述修復；App 編譯版本號未提供，使用 commit 識別，不推測版號。先前評論連續朗讀與其他無障礙穩定基準繼續保留。

## 2026-11-05：先前穩定基準（評論連續朗讀）

- main 合併提交：`66af9a7f47ebe9357b3037aab261410d7d5d086e`（PR #5）。
- 使用者確認的功能提交：`bce82730dcfbe2d89b46f0d976af0a663e32be48`。
- 實機環境：iOS 18.7.8、iPhone VoiceOver。使用者確認目前已非常穩定，基本不會自行停止，指定作為後續開發與 PiliPlus 官方版同步的穩定基準。
- 驗證範圍是本輪評論連續朗讀改善；不表示所有歷史功能已在同一天重新完整驗證。偶發停止的確切原因仍未證實，不能直接判定全是網路問題。
- 基準以 commit 識別，不填寫推算的 App／CI build 號；實際編譯版本由 OC 處理。
- 先前各專項已確認的行為繼續保留；評論連續朗讀的現行實作以 [專項基準](comment-read-all-current-baseline.md) 為準，歷史實驗文件不得覆蓋這份現行規格。


## 同步官方 PiliPlus 時必須保留

- iOS VoiceOver 的 `ReplyReadingSliver` 保留已載入評論，分批建立穩定的語意容器；新增下一頁不重建整條閱讀鏈。根評論排序為 0、排序控制項為 1、閱讀批次從 2 開始，頁尾固定在最後。
- 評論使用 `a11y-list-reply|oid|rpid`，不重新啟用舊 `a11y-read-reply|` 強制 page-turn、text-navigation hook 或逐頁 layoutChanged 通知。
- 評論翻頁外框提供真實 scrollPosition／scrollExtent，並監聽 ScrollMetricsNotification，在新增內容或視窗大小改變後更新 iOS 語意；不能退回 native contentSize 等於 viewport 的零範圍容器。
- `VoiceOverFeedScrollBridge` 對 `a11y-feed-scroll|replies` 優先呼叫 Flutter 原本捲動處理，只有未處理的邊界動作才轉交外框。不要讓每次正常自動捲動都發出自訂 pageScrolled 通知。
- 焦點離開評論後取消 timer 與尚未執行的 post-frame 捲動；同一評論的新請求取代舊請求。僅調整最近的列表 viewport，避免牽動外層頁面。
- 閱讀前方少於 30 則時預載至約 60 則；每頁完成後先讓 layout／semantics 更新，再繼續預載。自動預載保持安靜，不主動搬移焦點。
- 同一 controller 共用進行中的載入。最多五次嘗試，間隔 600ms、2s、5s、10s；失敗後自動載入冷卻 20 秒，由後續閱讀或捲動重新觸發，明確手動重試可立即執行。
- 重新整理／關閉時以 generation 使舊重試失效；舊請求完成不能清掉新的載入請求。
- 評論以伺服器 cursor.isEnd 為結尾依據之一，不因整頁被過濾成空就強制到底；成功空頁只在 cursor 前進時繼續追頁，嘗試次數仍有上限。
- 保留三指下滑往回翻、頂端重新整理，以及三指上滑前進、底端載入更多。自動預載不朗讀載入提示；明確手動操作可回報狀態。
- 保留樓中樓對外層語意的隔離，以及評論中的連結／@ 使用者轉輪。

## 主要實作位置

```text
lib/pages/common/a11y/reply_pagination.dart
lib/pages/common/reply_controller.dart
lib/pages/common/common_list_controller.dart
lib/common/a11y/voiceover_paged_scroll.dart
lib/common/a11y/a11y_focus_scroll.dart
lib/common/a11y/reply_semantics.dart
lib/pages/video/reply/view.dart
lib/pages/video/reply_reply/view.dart
ios/Runner/SceneDelegate.swift
```

## 實測界線與歷史文件

使用者確認基本不會自行停止，仍偶發停止。長時間離線、已載入內容耗盡時，不能保證 VoiceOver 等待網路後自行恢復朗讀。未宣稱弱網、離線及所有評論入口均已全面實測。

本文件取代先前指向 `186d41708881eabc5397d874b2f0ad64a911684c` 的回退候選基準。其他 `comment-read-all-*.md` 記錄的是排查過程；與本文件衝突時，以本文件及目前程式碼為準。不要依據先前「四十幾條」的體感描述挑選舊版回退。

未來更新官方版時，將上述行為移植至上游新結構，保留既有其他無障礙專項；由 OC 編譯後交使用者實機確認，再指定下一個穩定 commit。

# Accessibilibili 上游同步與無障礙維護指南

這份文件是給未來同步 PiliPlus 官方版本時使用的維護手冊。目標不是記錄所有功能，而是確保上游更新後，Accessibilibili 已經實機驗證過的 VoiceOver 行為不會被不小心覆蓋。

上游專案：`bggRGjQaUbCoE/PiliPlus`

本 fork：`Wentsy/Accessibilibili`

## 版本基準

- **目前已知完整實機驗證過的無障礙基準：`2a14e69b480dabb5d6bbf94bb17e8677a299f9c2`**
  - 包含既有低延遲三指翻頁、VoiceOver 原生翻頁回饋、主導航、評論與樓中樓、影片／評論時間、UP 頁、觀看紀錄、稍後再看等功能。
  - 另外包含 2026-09-04 完成實機驗證的 **iOS 原生富文字評論編輯器**：真正 `UITextView + NSTextAttachment`、圖片表情逐字朗讀、一張貼圖一個 selection slot、表情面板後鍵盤恢復、有貼圖時雙擊跳開頭／結尾、插入點位置公告、貼圖一次 Backspace 刪除及穩定刪除旁白。
- 舊的歷史完整基準：`f31c65e34cd5c05b6d5c3c9f020ed3450656fe2e`。
- 建立本文件早期版本時的程式快照：`3d86e42e9bca40491ba0813514fb6cfae7ebd79b`。

每當新版本完成 VoiceOver 實機驗證，應更新這一節的「目前已知完整實機驗證過的無障礙基準」。

iOS 富文字／圖片表情專項規格另見：

```text
docs/IOS_RICH_TEXT_VOICEOVER_BASELINE.md
```

## 最重要的原則

**不要把 PiliPlus 官方更新直接覆蓋到 `main`。**

官方更新應先進入獨立測試分支，例如：

```text
upstream-sync/2026-09-xx
```

在測試分支完成合併、編譯與 VoiceOver 實機驗證後，再合回 `main`。即使官方版本發生大型重構，現在可用的穩定版仍要能隨時回退。

## 建議同步流程

```bash
git checkout main
git pull origin main

git remote add upstream https://github.com/bggRGjQaUbCoE/PiliPlus.git  # 第一次才需要
git fetch upstream

git checkout -b upstream-sync/YYYY-MM-DD
git merge upstream/main
```

發生 conflict 時，不要整批選擇「接受上游版本」。先理解上游變更，再依本文件及各專項基準把 Accessibilibili 的無障礙意圖移植回新結構。

完成 conflict 後：

1. 靜態檢查／編譯檢查。
2. 交給 Hermes 打包 IPA。
3. 用 VoiceOver 實機跑快速驗收清單與受影響專項文件。
4. 全部通過後才合回 `main`。

建議保留 merge commit，不要為了歷史漂亮而強制重寫已發布的穩定歷史。

## 高風險核心區域

### 1. VoiceOver 捲動、焦點與翻頁

核心目錄：

```text
lib/common/a11y/
```

尤其注意：

```text
lib/common/a11y/a11y_focus_scroll.dart
lib/common/a11y/voiceover_paged_scroll.dart
lib/common/a11y/ios_accessibility_actions.dart
lib/common/a11y/reply_semantics.dart
lib/common/widgets/scroll_physics.dart
```

需要保留：

- VoiceOver 左右滑動焦點時，實際 viewport 跟著移動。
- 分頁 append/rebuild 不因焦點恢復跳回第一項。
- 三指上下翻頁真的移動畫面，不只是移 semantics focus。
- 主翻頁動畫維持約 `160ms` 的快速體感。
- fallback 原生翻頁回饋等待約 `120ms`，不要退回較長舊延遲。
- 翻頁完成後通知 iOS `UIAccessibility.Notification.pageScrolled`。
- 原生翻頁提示有短時間去重，避免同一手勢重複兩次。
- 路由 push/pop 不讓舊焦點把前一頁拉回頂部。

上游若重寫 ScrollView、ScrollPhysics、Sliver、ListView、GridView 或 semantics，這一區必須優先重新測試。

### 2. iOS 原生無障礙橋接與富文字編輯器

這一區現在是最高風險之一。

重點檔案：

```text
ios/Runner/AppDelegate.swift
lib/common/a11y/ios_accessibility_actions.dart
lib/common/widgets/flutter/text_field/ios_native_rich_text_field.dart
lib/common/widgets/flutter/text_field/controller.dart
lib/pages/video/reply_new/view.dart
```

需要保留：

- VoiceOver Magic Tap 播放／暫停橋接。
- Flutter → iOS 的 `pageScrolled` 原生通知。
- 不用自製音效取代 VoiceOver 原生翻頁回饋。
- iOS 評論／回覆富文字輸入欄位使用真正的 native `UITextView`。
- inline 圖片表情使用真正的 `NSTextAttachment`，不是只在 Flutter semantics 模擬。
- attachment `accessibilityLabel` 保留可理解 token，例如 `[doge]`、`[笑哭]`。
- **一張圖片表情永遠只佔一個 UTF-16 編輯槽**；目前 underlying buffer 使用一個 U+FFFC。
- Dart `RichTextEditingController` 繼續保存 raw token，發表時不能把 U+FFFC 當最終內容送出。
- native selection 與 Dart selection 維持一對一，不重新建立多字元 token offset mapping。
- 表情面板開啟造成 read-only 後，VoiceOver 回欄位雙擊可以切回鍵盤並繼續輸入。
- FocusNode 可能原本就保持 focus；native 解除 read-only 後仍需在正確時機 `becomeFirstResponder()`。
- VoiceOver activation 可能落在 `NSTextAttachment` 而不是 `UITextView`；attachment activation 必須能轉發既有操作。
- 有貼圖時，雙擊仍可快速在文字開頭／結尾切換，並在 attachment 路徑明確朗讀「插入點在開頭／結尾」。
- 貼圖一次 Backspace 整顆刪除，仍走原生 `deleteBackward → TextEditingDeltaDeletion → syncRichText()`。
- 只有 attachment 刪除時才補穩定 VoiceOver 回饋，例如「刪除 [doge]」；普通字元刪除不得被自訂旁白接管。

完整行為與已知失敗方案必須參照：

```text
docs/IOS_RICH_TEXT_VOICEOVER_BASELINE.md
```

#### 不可回退的技術判斷

以下方案已經過實機測試，不能當成目前 native rich editor 的等價替代：

- 單純把 U+FFFC 換成一般 Unicode 字元。
- Dart character cursor callback + announcement。
- hook `textInRange:`。
- 只改 `accessibilityAttributedValue`。
- `NSAccessibilityCustomTextAttribute`。
- 對 private `FlutterTextInputView` 假造 `attributedText`。
- 不真正參與編輯的 accessibility mirror `UITextView`。

目前成功的核心不是「騙 VoiceOver 這是 attachment」，而是讓 focused editor 本身真的使用 UIKit rich-text system。

### 3. 主導航

重點檔案：

```text
lib/pages/main/view.dart
lib/pages/main/controller.dart
```

主頁內容以目前選取 index 作為單一來源，使用 `IndexedStack` 保持底部導航選中狀態與實際畫面一致。

如果上游重新導入 `PageView` / `TabBarView`，要確認不會再次出現「底部選中已變，但內容仍停在首頁」。

### 4. 評論與樓中樓

需要保留：

- 主評論與樓中樓可以 VoiceOver 左右連續瀏覽。
- 三指翻頁正常。
- 載入更多後不跳回第一則。
- 展開樓中樓後，底部可找到「發表回覆」。
- VoiceOver 模式不出現重複浮動「發表回覆」。
- 關閉樓中樓後，主評論區「發表評論」恢復。
- 回覆樓層與回覆特定使用者的語意不可混淆。
- 評論時間放在整則旁白最後。

共用評論語義：

```text
lib/common/a11y/reply_semantics.dart
```

### 5. 影片卡與日期朗讀

重點檔案／區域：

```text
lib/common/widgets/video_card/video_card_v.dart
lib/common/widgets/video_card/video_card_h.dart
lib/pages/member_video/widgets/video_card_h_member_video.dart
lib/pages/history/widgets/item.dart
lib/pages/later/widgets/video_card_h_later.dart
lib/models_new/later/list.dart
lib/utils/date_utils.dart
```

旁白原則：

- 主要資訊先念，時間放最後。
- 固定日期自然中文，例如 `9月2日發佈`、`9月2日評論`。
- 較近期保留相對時間，例如 `3小時前發佈`、`20分鐘前評論`。
- UP 個人頁有時間就念，沒有就略過。
- App 推薦端沒有原生 `pubdate` 時，可背景補影片詳情但不阻塞首屏。
- 觀看紀錄用觀看時間：`9月2日看過`。
- 稍後再看使用 `add_at`，不是影片 `pubdate`：例如 `3小時前再看`、`9月2日再看`。
- 不把影片發布日誤當成加入稍後再看的日期。

### 6. 分頁列表

高風險類型包括：

- 首頁推薦
- App 推薦
- UP 個人影片列表
- 搜尋／一般橫向影片列表
- 主評論
- 樓中樓
- 相關影片

上游修改 controller `refresh()`、`addAll()`、列表 identity、key、預載距離、reload flag 或 ScrollPhysics 時，要優先檢查：

- 左右滑到列表邊界後「咚」一聲不能繼續。
- 載入下一頁後焦點跳回第一項。
- 畫面停在原地但旁白焦點跑到畫面外。
- 三指翻頁正常，但左右滑無法建立下一批 semantics node。

## 上游 conflict 處理原則

1. 先理解上游為什麼改，不直接保留舊檔整份覆蓋。
2. 保留上游 bug fix、新 API 與資料模型變更。
3. 再把 Accessibilibili 的無障礙「意圖」重新套入新結構。
4. 不只追求能編譯；VoiceOver semantics、focus、viewport、native text interaction 與實機行為才是驗收標準。
5. 已經穩定的機制沒有具體理由不要順手重構。

如果上游把某個 widget 完全重寫，通常應把無障礙行為移植到新 widget，而不是把舊 widget 整份硬塞回去。

但 iOS 富文字編輯器要特別注意：若新結構重新退回 plain Flutter text input，必須先證明 Character rotor 仍能逐張朗讀 inline attachment；否則視為 regression，不可只因程式較簡單就接受。

## 更新後 VoiceOver 快速驗收清單

同步官方版本後，至少跑以下項目：

- [ ] App 正常啟動、登入狀態正常、首頁有資料。
- [ ] 底部首頁／動態／我的導航切換時，選中狀態與內容一致。
- [ ] 首頁影片 VoiceOver 左右滑逐卡連續閱讀，實際畫面跟著焦點移動。
- [ ] 三指向上／向下翻頁正常、速度仍跟手，並有 VoiceOver 原生翻頁回饋。
- [ ] 翻頁或自動載入更多後不跳回第一項。
- [ ] Web 推薦影片可朗讀發布時間。
- [ ] App 推薦可取得時間時朗讀發布時間，首屏不被補抓阻塞。
- [ ] UP 個人頁影片可朗讀發布時間。
- [ ] 主評論可連續瀏覽、翻頁、點讚／點踩，時間朗讀正常。
- [ ] 展開樓中樓後可找到「發表回覆」。
- [ ] 關閉樓中樓後主評論「發表評論」重新出現。
- [ ] 樓中樓左右瀏覽不觸礁、不突然跳回第一則。
- [ ] 觀看紀錄最後朗讀正確「…看過」時間。
- [ ] 稍後再看使用 `add_at` 朗讀「…再看」，沒有拿 `pubdate` 冒充。
- [ ] 播放器 VoiceOver 進度調整正常。
- [ ] VoiceOver Magic Tap 能播放／暫停。
- [ ] 從影片、UP 頁、評論等頁面返回時焦點／viewport 不突然跳頂。

### iOS 富文字圖片表情必測

- [ ] 輸入「好耶」，插入 `[doge]`，再輸入「啊」，再插入 `[笑哭]`。
- [ ] 外層輸入欄位可朗讀帶名稱的完整內容。
- [ ] VoiceOver 轉輪切「字元」後，可逐格走過「好 → 耶 → [doge] → 啊 → [笑哭]」。
- [ ] 一張貼圖只佔一個插入位置。
- [ ] 表情面板開啟後，回輸入欄位雙擊能重新展開鍵盤並繼續打字。
- [ ] 有貼圖時雙擊仍可快速在文字開頭／結尾切換。
- [ ] attachment 路徑跳轉後朗讀「插入點在開頭／結尾」。
- [ ] 一次 Backspace 只刪一張貼圖。
- [ ] 刪貼圖穩定朗讀「刪除 [名稱]」，不亂念輸入第一個字或鍵盤推薦內容。
- [ ] 普通字元刪除仍使用使用者自己的 VoiceOver 輸入回饋設定。
- [ ] 發表後 server token 正常，不會送出裸 U+FFFC。

任何一項失敗，都不要急著合回 `main`。

## 推薦的分支策略

```text
main
  └─ 已驗證、可日常使用版本

upstream-sync/YYYY-MM-DD
  └─ 合入 PiliPlus 官方最新版、處理 conflict、交 Hermes 打包、實機測試
```

大版本更新前可建立保險 tag，例如：

```text
stable-2026-09-accessibility
```

目前如果要標記富文字完成後的穩定點，應至少能回到：

```text
2a14e69b480dabb5d6bbf94bb17e8677a299f9c2
```

## 給 Hermes／未來維護者的短版指令

> 同步 PiliPlus 上游時，先從 Accessibilibili `main` 建立獨立 `upstream-sync` 分支，再合入 `bggRGjQaUbCoE/PiliPlus:main`。不要直接覆蓋本 fork 的無障礙檔案。發生 conflict 時要保留上游新功能，同時重新套回 Accessibilibili 的 VoiceOver semantics、焦點／viewport 同步、低延遲三指翻頁、iOS `pageScrolled`、評論／樓中樓、日期朗讀，以及 iOS native `UITextView + NSTextAttachment` 富文字編輯基準。圖片表情必須維持一張一個 UTF-16 slot、Character rotor 可朗讀 `[doge]` 等名稱、表情面板後可恢復鍵盤、有貼圖時可雙擊跳頭尾、一次 Backspace 刪一張且刪除旁白穩定。編譯後必須跑本文件與 `docs/IOS_RICH_TEXT_VOICEOVER_BASELINE.md` 的 VoiceOver 實機清單，全部通過才合回 `main`。

---

這份文件應隨 Accessibilibili 的穩定功能演進一起更新。它的用途不是阻止上游更新，而是讓更新可以安全進來，而不用每次重新發明一次已經解決過的無障礙問題。

## 貼圖／表情的 VoiceOver 維護規則

### 選擇面板／Grid

- 貼圖不能只暴露圖片本身；每張可插入貼圖都應是一個穩定 VoiceOver 語義節點。
- 優先使用 emoji／alias／文字名稱；沒有名稱至少朗讀「貼圖」。
- 貼圖入口、Grid viewport、分類 Tab 與插入／送出 callback 的規則依 `docs/VOICEOVER_SEMANTICS_BASELINE.md`。

### focused editor 內的 inline 圖片表情

這和「表情選擇面板」是不同問題，不可混為一談。

- focused editor 的 inline 圖片表情必須使用 iOS native rich-text 基準。
- 不要用選擇面板的 Flutter `Semantics(label:)` 思路取代真正的 `NSTextAttachment`。
- 一張 attachment 一個 UTF-16 slot。
- Character rotor 必須取得名稱。
- selection、鍵盤恢復、邊界跳轉與 Backspace 必須一起驗收。

完整規格：`docs/IOS_RICH_TEXT_VOICEOVER_BASELINE.md`。
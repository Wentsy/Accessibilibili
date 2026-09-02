# Accessibilibili 上游同步與無障礙維護指南

這份文件是給未來同步 PiliPlus 官方版本時使用的維護手冊。目標不是記錄所有功能，而是確保上游更新後，Accessibilibili 已經實機驗證過的 VoiceOver 行為不會被不小心覆蓋。

上游專案：`bggRGjQaUbCoE/PiliPlus`

本 fork：`Wentsy/Accessibilibili`

## 版本基準

- 已知完整實機驗證過的功能基準：`f31c65e34cd5c05b6d5c3c9f020ed3450656fe2e`
  - 包含低延遲三指翻頁、VoiceOver 原生翻頁回饋、主導航、評論與樓中樓、影片／評論時間、UP 頁與 App 推薦時間等已驗證功能。
- 建立本文件時的程式快照：`3d86e42e9bca40491ba0813514fb6cfae7ebd79b`
  - 另外加入中文月日朗讀格式、觀看紀錄「…看過」、稍後再看 `add_at → …再看` 等時間朗讀整理。

每當新版本完成實機驗證，建議更新這一節的「已知完整實機驗證過的功能基準」。

## 最重要的原則

**不要把 PiliPlus 官方更新直接覆蓋到 `main`。**

官方更新應先進入獨立測試分支，例如：

```text
upstream-sync/2026-09-xx
```

在測試分支完成合併、編譯與 VoiceOver 實機驗證後，再合回 `main`。

這樣即使官方版本發生大型重構，現在可用的穩定版仍然永遠保留。

## 建議同步流程

本機 Git 可採用以下流程：

```bash
git checkout main
git pull origin main

git remote add upstream https://github.com/bggRGjQaUbCoE/PiliPlus.git  # 第一次才需要
git fetch upstream

git checkout -b upstream-sync/YYYY-MM-DD
git merge upstream/main
```

如果發生 conflict，不要直接整批選擇「接受上游版本」。先對照本文件的核心功能與高風險檔案逐一處理。

完成 conflict 處理後：

1. 先做靜態檢查／編譯檢查。
2. 交給 Hermes 打包 IPA。
3. 用 VoiceOver 實機跑完下方驗收清單。
4. 全部通過後才合回 `main`。

建議保留 merge commit，不要為了讓歷史漂亮而強制重寫已發布的穩定歷史。

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

需要保留的行為：

- VoiceOver 左右滑動焦點時，實際 viewport 必須跟著移動。
- 分頁 append/rebuild 時不得因焦點恢復而跳回第一項。
- 三指上下翻頁必須真的移動畫面，而不是只移動語義焦點。
- 主翻頁動畫目前為約 `160ms`，以保持快速但仍平滑的體感。
- fallback 的原生翻頁回饋等待約 `120ms`，不要退回較長的舊延遲。
- 翻頁完成後仍要通知 iOS `UIAccessibility.Notification.pageScrolled`。
- 原生翻頁提示有短時間去重，避免一次手勢重複響兩次。
- 路由 push/pop 過程不要讓舊焦點把前一頁拉回頂部。

如果上游重寫 ScrollView、ScrollPhysics、Sliver、ListView、GridView 或 semantics，這一區必須優先重新測試。

### 2. iOS 原生無障礙橋接

重點檔案：

```text
ios/Runner/AppDelegate.swift
lib/common/a11y/ios_accessibility_actions.dart
```

需要保留：

- VoiceOver Magic Tap 播放／暫停橋接。
- Flutter → iOS 的 `pageScrolled` 原生通知。
- 不要用自製音效取代 VoiceOver 原生翻頁回饋。

### 3. 主導航

重點檔案：

```text
lib/pages/main/view.dart
lib/pages/main/controller.dart
```

目前主頁內容以目前選取 index 作為單一來源，使用 `IndexedStack` 保持底部導航選中狀態與實際畫面一致。

如果上游重新導入 `PageView` / `TabBarView`，要特別確認不會再次出現「底部選中已變，但內容仍停在首頁」的問題。

### 4. 評論與樓中樓

需要保留：

- 主評論與樓中樓可以 VoiceOver 左右連續瀏覽。
- 三指翻頁正常。
- 載入更多後不跳回第一則。
- 展開樓中樓後，底部可找到「發表回覆」。
- VoiceOver 模式不出現重複的浮動「發表回覆」。
- 關閉樓中樓後，主評論區「發表評論」會恢復。
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

目前旁白原則：

- 主要資訊先念，時間放最後。
- 固定日期以自然中文朗讀，例如 `9月2日發佈`、`9月2日評論`。
- 較近期時間保留相對格式，例如 `3小時前發佈`、`20分鐘前評論`。
- UP 個人頁有時間就念，沒有就略過。
- App 推薦端沒有原生 `pubdate` 時，可背景補影片詳情，但不阻塞首屏。
- 觀看紀錄使用觀看時間：`9月2日看過`。
- 稍後再看使用 `add_at`，不是影片 `pubdate`：例如 `3小時前再看`、`9月2日再看`。
- 不要把影片發布日誤當成加入稍後再看的日期。

### 6. 分頁列表

曾特別處理過的高風險類型包括：

- 首頁推薦
- App 推薦
- UP 個人影片列表
- 搜尋／一般橫向影片列表
- 主評論
- 樓中樓
- 相關影片

如果上游修改 controller 的 `refresh()`、`addAll()`、列表 identity、key、預載距離、reload flag 或 ScrollPhysics，要優先檢查 VoiceOver 是否重新出現：

- 左右滑到列表邊界後「咚」一聲不能繼續。
- 載入下一頁後焦點跳回第一項。
- 畫面停在原地但旁白焦點跑到畫面外。
- 三指翻頁正常，但左右滑無法建立下一批 semantics node。

## 上游 conflict 處理原則

遇到同一檔案 conflict 時，判斷順序：

1. 先理解上游為什麼改，不要直接保留舊檔整份覆蓋。
2. 保留上游 bug fix、新 API 與資料模型變更。
3. 再把 Accessibilibili 的無障礙「意圖」重新套入新結構。
4. 不要只追求程式能編譯；VoiceOver 的 semantics、focus、viewport 與實機行為才是驗收標準。
5. 已經穩定的機制沒有具體理由不要順手重構。

如果上游把某個 widget 完全重寫，通常應把無障礙行為重新移植到新 widget，而不是強行把舊 widget 整份塞回去。

## 更新後 VoiceOver 快速驗收清單

同步官方版本後，至少跑以下項目：

- [ ] App 可正常啟動、登入狀態正常、首頁有資料。
- [ ] 底部首頁／動態／我的等導航切換時，選中狀態與內容一致。
- [ ] 首頁影片 VoiceOver 左右滑可逐卡連續閱讀，實際畫面跟著焦點移動。
- [ ] 三指向上／向下翻頁能正常捲動畫面，速度仍跟手，並有 VoiceOver 原生翻頁音效。
- [ ] 翻頁或自動載入更多後不跳回第一項。
- [ ] Web 推薦影片可朗讀發布時間。
- [ ] App 推薦在可取得時間時可朗讀發布時間，首屏不被時間補抓阻塞。
- [ ] UP 個人頁影片可朗讀發布時間。
- [ ] 主評論可連續瀏覽、翻頁、點讚／點踩，時間朗讀正常。
- [ ] 展開樓中樓後可以找到「發表回覆」。
- [ ] 關閉樓中樓後主評論「發表評論」重新出現。
- [ ] 樓中樓左右瀏覽不觸礁、不突然跳回第一則。
- [ ] 觀看紀錄最後可朗讀正確的「…看過」時間。
- [ ] 稍後再看使用 `add_at` 朗讀「…再看」，沒有拿 `pubdate` 冒充。
- [ ] 播放器 VoiceOver 進度調整正常。
- [ ] VoiceOver Magic Tap 能播放／暫停。
- [ ] 從影片、UP 頁、評論等頁面返回時焦點／viewport 不會突然跳頂。

如果這份清單任何一項失敗，不要急著合回 `main`。

## 推薦的分支策略

```text
main
  └─ 已驗證、可日常使用版本

upstream-sync/YYYY-MM-DD
  └─ 合入 PiliPlus 官方最新版、處理 conflict、交 Hermes 打包、實機測試
```

必要時也可以在大版本更新前建立保險 tag，例如：

```text
stable-2026-09-accessibility
```

這樣任何時候都能快速回到已知可用版本。

## 給 Hermes／未來維護者的短版指令

> 同步 PiliPlus 上游時，先從 Accessibilibili `main` 建立獨立 `upstream-sync` 分支，再合入 `bggRGjQaUbCoE/PiliPlus:main`。不要直接覆蓋本 fork 的無障礙檔案。發生 conflict 時要保留上游新功能，同時重新套回 Accessibilibili 的 VoiceOver semantics、焦點／viewport 同步、低延遲三指翻頁、iOS `pageScrolled`、評論／樓中樓與日期朗讀行為。編譯後必須跑本文件的 VoiceOver 快速驗收清單，全部通過才合回 `main`。

---

這份文件應隨著 Accessibilibili 的穩定功能演進一起更新。它的用途不是阻止上游更新，而是讓更新可以安全進來，而不用每次重新發明一次已經解決過的無障礙問題。


## 貼圖／表情的 VoiceOver 維護規則

- 貼圖不能只暴露圖片本身；每個可插入的貼圖都應是一個穩定的 VoiceOver 語義節點。
- 優先使用貼圖的 emoji／alias／文字名稱作為朗讀標籤；沒有名稱時至少朗讀「貼圖」。
- 標籤應讓使用者知道這是貼圖，並提供「點兩下插入這個貼圖」提示。
- 點擊與 VoiceOver 的 onTap 必須共用同一個插入 callback，避免視覺點擊和無障礙操作行為分歧。
- 插入成功後可提供簡短回饋，例如「已插入○○貼圖」。
- 一般表情面板與直播貼圖面板都要驗收；新增或重構貼圖 widget 時，不可只測影片卡／評論而漏掉貼圖。

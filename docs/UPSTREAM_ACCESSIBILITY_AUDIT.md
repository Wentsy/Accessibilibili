# Accessibilibili 與 PiliPlus 官方版無障礙差異稽核

這份文件用來記錄 Accessibilibili 相對 PiliPlus 官方版已確認存在的 VoiceOver／無障礙差異，避免未來同步上游時，只記得近期改動，卻把早期已經成熟的無障礙行為弄丟。

本文件應與以下兩份文件一起使用：

- `docs/ACCESSIBILITY_MAINTENANCE.md`：上游同步流程與整體驗收。
- `docs/VOICEOVER_SEMANTICS_BASELINE.md`：一滑一整條的語義品質基準。

> 注意：這是一份「差異與驗收基準」文件，不代表 PiliPlus 官方永遠不會加入相同功能。每次同步官方新版時，都應重新比對上游現況。

## 2026-09-02 稽核摘要

此次直接以 `Wentsy/Accessibilibili:main` 對照 `bggRGjQaUbCoE/PiliPlus:main`，確認除了已經記錄的影片卡、評論、三指翻頁、焦點同步、日期朗讀與 Magic Tap 之外，還有以下容易被遺漏的無障礙差異。

## 1. 貼圖／表情選擇面板

### Accessibilibili 目前已確認的行為

一般表情面板 `lib/pages/emote/view.dart` 會：

- 每個可插入的表情建立獨立、可操作的 `Semantics` 節點。
- 優先使用 alias，沒有 alias 時使用表情文字名稱。
- 朗讀例如「○○ 表情」，而不是只讓 VoiceOver 遇到一張沒有名稱的圖片。
- 提供「點兩下插入這個表情」提示。
- 視覺點擊與 VoiceOver `onTap` 共用同一個 `choose()` callback。
- 插入成功後透過無障礙回饋朗讀「已插入○○表情」。
- 「管理表情包」按鈕有明確 label 與 hint。
- 表情包分組 Tab 有「表情包第 N 組」語義，不只暴露一張封面圖。

PiliPlus 官方同一個表情面板目前沒有上述這組明確的 `Semantics` 包裝、插入回饋與表情包分組標籤。

### 直播貼圖範圍特別說明

曾經有一次嘗試把相同策略套到 `lib/pages/live_emote/view.dart`，但該程式修改隨後已完整 revert，以保留既有穩定行為。

因此目前文件中的「貼圖／表情面板都要驗收」應理解為**維護與驗收原則**，不能解讀成「直播貼圖目前已完成同樣的無障礙改造」。

同步上游時至少要確認一般表情面板不退化；如果未來重新處理直播貼圖，應單獨實機驗證後再把它列為已完成基準。

## 2. 共用網路圖片的語義降噪

重點檔案：

```text
lib/common/widgets/image/network_img_layer.dart
```

Accessibilibili 會在共用 `CachedNetworkImage` 外層排除圖片本身的內部語義，避免下列視覺元素自動變成沒有操作價值的 VoiceOver 焦點：

- 影片封面
- 頭像
- 角標／縮圖
- 上層 widget 已經提供完整 label 的圖片

這是「一滑一整條」能保持乾淨的重要底層條件。PiliPlus 官方目前的共用網路圖片層沒有這個排除語義包裝。

### 維護原則

- 裝飾性圖片不應搶 VoiceOver 焦點。
- 真正需要被理解的圖片，應由更高層的內容 widget 提供有意義的 label，而不是依賴圖片 URL 或底層 image widget 自動產生語義。
- 如果上游重寫圖片元件，要特別檢查首頁、評論、UP 頁、通知、貼圖面板是否突然多出大量「圖片」焦點。

## 3. 播放器進度條的完整可調整語義

重點檔案：

```text
lib/common/widgets/progress_bar/audio_video_progress_bar.dart
```

Accessibilibili 的播放進度條不是只把官方「進度條」保留下來，而是重新整理成適合 VoiceOver 的可調整控制：

- label：`影片播放進度`
- value 同時包含目前時間、總時長與百分比。
- hint 明確說明「向上滑快轉 10 秒，向下滑倒帶 10 秒」。
- VoiceOver Increase / Decrease 固定以 ±10 秒移動，不使用影片長度百分比。
- `increasedValue` / `decreasedValue` 會回報調整後的時間與百分比。
- seek callback 使用播放器實際需要的毫秒單位，避免秒／毫秒錯位造成錯誤跳轉。

PiliPlus 官方目前主要以百分比朗讀，Increase / Decrease 使用 ±5%，資訊量與可預測性都不同。

### 驗收

- [ ] VoiceOver 聚焦進度條時會知道這是影片播放進度。
- [ ] 能聽到目前時間、總時長與百分比。
- [ ] 向上滑實際快轉約 10 秒。
- [ ] 向下滑實際倒帶約 10 秒。
- [ ] 調整一次不是只跳 10 毫秒，也不應因影片很長而一次跳很大段。

## 4. 播放器按鈕與播放狀態語義

重點檔案：

```text
lib/plugin/pl_player/widgets/common_btn.dart
lib/plugin/pl_player/widgets/play_pause_btn.dart
```

Accessibilibili 對播放器控制按鈕增加了明確的按鈕角色、label、enabled 狀態與操作提示，避免只剩 icon／GestureDetector。

播放／暫停按鈕還會：

- 依即時播放狀態更新 label 為「播放」或「暫停」。
- value 會說明「正在播放」或「已暫停」。
- hint 會跟著目前狀態改變。
- 播放狀態 stream 更新後會重建語義，避免畫面已暫停但 VoiceOver 還說「暫停」或反過來。

### 驗收

- [ ] 播放／暫停按鈕不只朗讀一個無意義 icon。
- [ ] 播放中時操作名稱為「暫停」，暫停時為「播放」。
- [ ] 狀態切換後 VoiceOver 語義立即同步。
- [ ] 其他播放器 icon 若有 tooltip，VoiceOver 可取得相同名稱與「點兩下啟用」提示。

## 5. 影片詳情互動按鈕的狀態與即時回饋

重點檔案：

```text
lib/pages/video/introduction/ugc/widgets/action_item.dart
lib/common/a11y/a11y_action_feedback.dart
```

Accessibilibili 對影片詳情頁常見的互動控制補上明確的狀態語義：

- 按鈕有完整 label。
- `selected` 反映已點讚／已收藏等選取狀態。
- `value` 會表達「已啟用／未啟用」。
- 使用 `liveRegion`，狀態變化時 VoiceOver 能即時察覺。
- 另外有共用 `a11yActionFeedback()`，讓成功／失敗等結果不只顯示視覺 Toast，也能有語音回饋。

PiliPlus 官方同一個 `ActionItem` 目前沒有這層外部 `Semantics` 狀態包裝。

### 驗收

- [ ] 點讚、收藏等控制能讀出目前是否已啟用。
- [ ] 執行操作後狀態不需離開再回來才更新。
- [ ] 關鍵成功／失敗結果不能只有 Toast、沒有 VoiceOver 回饋。

## 6. 底部浮動導航列的完整按鈕與選中語義

重點檔案：

```text
lib/common/widgets/floating_navigation_bar.dart
```

Accessibilibili 對每個 navigation destination 明確建立：

- `button: true`
- 完整頁籤 label
- `selected` 狀態
- 排除 icon 與文字重複形成多個子焦點

PiliPlus 官方目前該位置主要仍是 `GestureDetector` 包裹視覺 layout，沒有 Accessibilibili 這層明確的完整 destination 語義。

### 驗收

- [ ] VoiceOver 能以一個焦點找到一個底部分頁。
- [ ] 會朗讀分頁名稱。
- [ ] 目前所在分頁會被標示為已選取。
- [ ] icon 與文字不應拆成兩個重複焦點。

## 7. 三指翻頁不只涵蓋影片與評論頁

`VoiceOverPagedScroll` 已套用到多種非影片內容列表。已確認的差異檔案包含例如：

```text
lib/pages/article_list/view.dart
lib/pages/dynamics_tab/view.dart
lib/pages/fav/video/view.dart
lib/pages/fav_detail/view.dart
lib/pages/follow_type/view.dart
lib/pages/history/view.dart
lib/pages/hot/view.dart
lib/pages/live/view.dart
lib/pages/member_dynamics/view.dart
lib/pages/msg_feed_top/at_me/view.dart
lib/pages/msg_feed_top/like_me/view.dart
lib/pages/msg_feed_top/reply_me/view.dart
lib/pages/msg_feed_top/sys_msg/view.dart
lib/pages/subscription/view.dart
lib/pages/video/related/view.dart
lib/pages/whisper/view.dart
```

以「@我的」頁面為例，Accessibilibili 會用 `VoiceOverPagedScroll` 包住真正的 `CustomScrollView`；PiliPlus 官方目前同一頁面直接使用 `CustomScrollView`。

### 維護原則

不要把「三指翻頁」只當成首頁與評論區功能。同步上游後，至少抽查：

- [ ] 動態／熱門／追蹤類列表
- [ ] 收藏與收藏詳情
- [ ] 通知：@我的、讚我的、回覆我的、系統通知
- [ ] 私訊列表
- [ ] 訂閱／文章／直播等長列表

如果上游重寫某一頁的 ScrollView，該頁可能單獨失去三指翻頁，即使首頁仍然正常。

## 8. 「一滑一整條」與圖片降噪必須一起驗收

影片卡與評論的一滑一整條已在 `VOICEOVER_SEMANTICS_BASELINE.md` 詳細記錄，但此次官方比對再次確認：這個體驗不只依賴最外層 `Semantics`，也依賴共用圖片、Badge、Icon 等子元件不要重新暴露語義。

因此未來若出現以下現象，即使卡片 label 看起來還在，也應視為 regression：

- 一支影片先讀「圖片」再讀完整影片卡。
- 一則評論前面多出頭像焦點。
- 播放器按鈕同時被讀成 icon 與按鈕兩次。
- 表情面板同一個表情要滑兩次才能操作。

## 上游同步後建議新增的快速驗收項目

除了原維護指南的清單，再補以下項目：

- [ ] 一般表情面板每個表情有可理解名稱，可點兩下插入，插入後有簡短 VoiceOver 回饋。
- [ ] 表情包管理按鈕與表情包分組 Tab 都有清楚語義。
- [ ] 影片／評論／通知列表沒有大量無意義的「圖片」獨立焦點。
- [ ] 播放器進度條能讀目前時間／總時長／百分比，並以 ±10 秒調整。
- [ ] 播放／暫停按鈕名稱與目前播放狀態一致。
- [ ] 影片詳情的讚／收藏等控制能讀出 selected 狀態，操作後狀態會更新。
- [ ] 底部導航每一頁是一個按鈕焦點，且目前頁籤有 selected 狀態。
- [ ] 至少抽查一個通知頁與一個非影片長列表，確認三指翻頁沒有只剩首頁能用。

## 不應誤記為目前已完成的項目

- 直播貼圖面板曾有試驗性 VoiceOver Semantics 改造，但該程式變更已 revert；在重新實作並實機驗證以前，不應把它列為目前穩定功能。

---

這份稽核的目的不是追求「跟官方不同越多越好」，而是把已經真正改善 VoiceOver 日常操作的差異留下可驗收的規格。同步 PiliPlus 上游時，應保留這些使用體驗，同時吸收上游的新功能與 bug fix。
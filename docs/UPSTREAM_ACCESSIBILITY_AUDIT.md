# Accessibilibili 與 PiliPlus 官方版無障礙差異稽核

這份文件記錄 Accessibilibili 相對 PiliPlus 官方版已確認存在、且需要在未來上游同步時保留的 VoiceOver／無障礙差異。

本文件應與以下文件一起使用：

- `docs/ACCESSIBILITY_MAINTENANCE.md`：上游同步流程與整體驗收。
- `docs/VOICEOVER_SEMANTICS_BASELINE.md`：完整內容單位、一滑一整條與全域貼圖／表情基準。
- `docs/LIVE_ACCESSIBILITY_BASELINE.md`：直播推薦、直播貼圖、即時彈幕、三指翻頁與刷新專項穩定基準。

> 注意：這是一份「差異與驗收基準」文件，不代表 PiliPlus 官方永遠不會加入相同功能。每次同步官方新版時，都應重新比對上游現況，保留使用體驗而不是盲目保留舊程式碼。

## 2026-09-03 稽核摘要

目前 Accessibilibili 已實機確認的核心無障礙差異包含：

- 影片卡、評論、直播推薦與直播彈幕的一滑一整條。
- 焦點與真實 viewport 同步。
- 多頁面 VoiceOver 三指翻頁。
- 直播聊天室整頁三指翻頁、最新端更新／刷新與最舊端提示。
- 直播新彈幕閱讀暫停與焦點穩定。
- 全域貼圖／表情命名、可操作語義、Grid 焦點同步與分類 Tab。
- 直播彈幕精確到秒的 VoiceOver 發送時間。
- 觀看紀錄未開播直播狀態直接併入卡片語義。
- 播放器進度 ±10 秒、播放／暫停狀態語義與 Magic Tap。
- 圖片／Badge／Icon 的語義降噪。
- 日期與相對時間的 VoiceOver 友善格式。

以下分項是未來同步 PiliPlus 時的高風險差異。

---

## 1. 貼圖／表情選擇面板是全域無障礙標準

### 一般表情面板

重點檔案例如：

```text
lib/pages/emote/view.dart
```

Accessibilibili 會：

- 每個可插入表情建立獨立、可操作的 `Semantics` 節點。
- 優先使用 alias／文字名稱，而不是只暴露圖片。
- 提供「點兩下插入這個表情」等與實際行為一致的提示。
- 視覺點擊與 VoiceOver `onTap` 共用同一個 callback。
- 插入成功後提供簡短 VoiceOver 回饋。
- 管理表情包按鈕與分組 Tab 有明確 label／hint。
- 分組圖片不額外搶焦點。

### 直播貼圖已完成，不再是 revert 狀態

重點檔案：

```text
lib/pages/live_emote/view.dart
lib/pages/live_room/send_danmaku/view.dart
```

舊稽核曾寫過「直播貼圖試驗性改造已 revert，因此尚未完成」。**這已不是目前狀態。**

2026-09-03 前後的實機驗收已確認直播貼圖完整支援：

- 貼圖名稱可朗讀。
- 無名稱有「貼圖」fallback。
- 插入型／直接送出型貼圖可正常操作。
- 插入／送出後有 VoiceOver 回饋。
- Grid viewport 跟著 VoiceOver 焦點移動。
- 分組 Tab 可朗讀、可點兩下切換。
- Tab 外層不能使用會吃掉 TabBar 操作的 `excludeSemantics: true`。
- 入口使用「表情與貼圖」、「鍵盤」、「快速發送貼圖」等功能名稱，而不是只念笑臉圖或「按鈕」。

因此未來同步上游時，**一般表情與直播貼圖都屬於已完成、需保留的無障礙功能。**

---

## 2. 共用網路圖片的語義降噪

重點檔案：

```text
lib/common/widgets/image/network_img_layer.dart
```

Accessibilibili 會排除共用圖片本身沒有操作價值的內部語義，避免影片封面、頭像、角標、縮圖等自動變成 VoiceOver 獨立焦點。

這是「一滑一整條」能保持乾淨的重要底層條件。

### 維護原則

- 裝飾性圖片不應搶焦點。
- 真正需要被理解的圖片資訊，應由更高層內容 widget 的完整 label 提供。
- 上游若重寫圖片元件，要抽查首頁、評論、UP 頁、通知、觀看紀錄、貼圖與直播頁是否突然多出大量「圖片」焦點。

---

## 3. 播放器進度條的完整可調整語義

重點檔案：

```text
lib/common/widgets/progress_bar/audio_video_progress_bar.dart
```

Accessibilibili 的影片播放進度條包含：

- label：`影片播放進度`。
- value：目前時間、總時長與百分比。
- hint：向上滑快轉 10 秒、向下滑倒帶 10 秒。
- VoiceOver Increase / Decrease 固定 ±10 秒，不以影片百分比調整。
- `increasedValue` / `decreasedValue` 回報調整後時間與百分比。
- seek callback 使用正確毫秒單位。

### 驗收

- [ ] 聚焦進度條時知道它是影片播放進度。
- [ ] 能聽到目前時間、總時長與百分比。
- [ ] 向上滑約快轉 10 秒。
- [ ] 向下滑約倒帶 10 秒。

---

## 4. 播放器按鈕、播放狀態與 Magic Tap

重點檔案例如：

```text
lib/plugin/pl_player/widgets/common_btn.dart
lib/plugin/pl_player/widgets/play_pause_btn.dart
ios/Runner/AppDelegate.swift
```

Accessibilibili 對播放器控制補上：

- 明確按鈕角色與功能名稱。
- 播放／暫停 label 隨即時狀態更新。
- value 表達「正在播放」／「已暫停」。
- hint 與下一步操作一致。
- 狀態 stream 更新後語義同步重建。
- iOS 原生 Magic Tap 保留既有穩定行為。

### 維護原則

不要因上游重寫播放器 UI 就把明確 semantics 或 native Magic Tap 丟掉。

---

## 5. 影片詳情互動按鈕的狀態與即時回饋

重點檔案：

```text
lib/pages/video/introduction/ugc/widgets/action_item.dart
lib/common/a11y/a11y_action_feedback.dart
```

Accessibilibili 對讚、收藏等控制補上：

- 完整 label。
- `selected` 狀態。
- value 表達已啟用／未啟用。
- `liveRegion` 讓狀態更新可被 VoiceOver 察覺。
- 關鍵成功／失敗結果可透過 `a11yActionFeedback()` 提供語音回饋。

但不要機械地把 announce 用在所有場景；若已知狀態可在聚焦時直接放入原本 `Semantics.label`，應優先使用穩定的完整語義，避免公告被後續焦點事件中斷。

---

## 6. 底部浮動導航列的完整按鈕與選中語義

重點檔案：

```text
lib/common/widgets/floating_navigation_bar.dart
```

每個 destination 應具有：

- `button: true`。
- 完整頁籤 label。
- `selected` 狀態。
- icon 與文字不拆成重複焦點。

同步上游後要確認首頁底部導航沒有退回成只有 GestureDetector／icon 的半無障礙狀態。

---

## 7. 三指翻頁是全域能力，不只首頁與評論

重點元件：

```text
lib/common/a11y/voiceover_paged_scroll.dart
```

`VoiceOverPagedScroll` 已套用到多種長列表，例如：

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

共用體感基準約：

```text
0.85 viewport / 160ms / easeOutCubic
```

並透過 iOS `pageScrolled` 提供原生 VoiceOver 翻頁回饋。

### 維護原則

不要只驗首頁。上游重寫任何 ScrollView，都可能讓單一頁面失去三指翻頁。

至少抽查：

- [ ] 動態／熱門／追蹤類列表。
- [ ] 收藏與收藏詳情。
- [ ] 觀看紀錄。
- [ ] 通知：@我的、讚我的、回覆我的、系統通知。
- [ ] 私訊列表。
- [ ] 訂閱／文章／直播等長列表。

---

## 8. 直播觀看頁三指翻頁是特殊高風險差異

重點檔案：

```text
lib/pages/live_room/view.dart
lib/pages/live_room/widgets/chat_panel.dart
lib/pages/live_room/controller.dart
lib/common/a11y/voiceover_paged_scroll.dart
```

直播聊天室不是單純把 `VoiceOverPagedScroll` 包在 ListView 外而已。

### 已實機確認的穩定行為

- 聊天室方向：**上方較舊、下方較新**。
- 三指向下：往較舊彈幕。
- 三指向上：往較新彈幕。
- 三指翻頁作用範圍涵蓋整個非全螢幕直播觀看頁。
- VoiceOver 焦點在發送彈幕、主播資訊或其他控制時，三指仍操作聊天室 ScrollController。
- 最舊端再三指向下只提示「已到最舊彈幕」。
- 最新端再三指向上：有排隊訊息則更新到最新；無排隊訊息則重新抓最新彈幕。
- 最新端刷新有「正在重新整理彈幕」與成功／失敗回饋。
- 刷新不重新載入播放器／直播串流。

### 上游同步風險

如果只把 `chat_panel.dart` 的 ListView 保留下來、卻移除直播頁外層的翻頁語義，會退化成「只有焦點在彈幕區才可翻頁」。這已在 5452 實機出現過，屬於已知 regression。

---

## 9. 直播新彈幕不得打斷舊訊息閱讀

直播即時訊息需要額外保護：

- VoiceOver 開始閱讀聊天室後，使用獨立閱讀暫停狀態（目前 `a11yChatPaused`）。
- 一般 ScrollController listener 不得解除這個狀態。
- 新彈幕可接收但先排隊，不立即讓列表 rebuild／自動捲動。
- 新彈幕不得把焦點拉到底部，也不得因 rebuild 把焦點跳回列表第一條。
- 每條彈幕需要穩定 semantic key。
- 單指讀到目前最後一條時可揭露排隊內容，但不強制跳到底部。
- 使用者主動三指更新或使用「回到底部」時，才解除暫停並回到最新端。

這一套行為已實機確認通過，未來不能退回只靠 `disableAutoScroll` 的一般觸控邏輯。

---

## 10. 直播彈幕是一滑一條，且時間精確到秒

重點檔案：

```text
lib/pages/live_room/widgets/chat_panel.dart
```

Accessibilibili 將一條彈幕整合成一個完整 semantic node：

一般：

```text
某某 說：內容，今天1點23分45秒發送
```

回覆：

```text
某某 回覆 某某：內容，今天1點23分45秒發送
```

規則：

- 發送者、回覆對象、內容、貼圖文字與時間不拆成多個焦點。
- 內嵌貼圖有名稱或「貼圖」fallback。
- 時間取可靠 UNIX 秒級 `ts`。
- 精確到秒並放在最後。
- 小時使用「點」而不是「時」，例如 `1點13分45秒`；這是實機高語速辨識後確認的可讀性修正。

---

## 11. 「回到底部」對 VoiceOver 是有價值的快速操作

「回到底部」是上游原有介面，不是 Accessibilibili 新造按鈕。

在舊彈幕閱讀不再被新訊息搶焦點後，實機確認這顆按鈕對 VoiceOver 有實際價值，因此目前基準是：

- VoiceOver 可聚焦「回到底部」。
- 點兩下解除閱讀暫停。
- 揭露排隊的新訊息。
- 跳到列表最新端。
- 它是快速捷徑，不是唯一方法；三指向上與單指閱讀仍可回到最新內容。

未來不要因舊的 workaround 紀錄再次把它對 VoiceOver 隱藏。

---

## 12. 觀看紀錄中的未開播直播狀態

重點檔案：

```text
lib/pages/history/widgets/item.dart
```

當 `business == 'live' && liveStatus != 1` 時，Accessibilibili 會把狀態直接併入觀看紀錄卡片完整語義：

```text
直播標題，主播名稱，觀看時間，主播目前未開播
```

並移除「點兩下繼續觀看」這種不符合實際狀態的 hint。

### 為什麼不依賴點擊後 announce

實機曾確認：點兩下未開播直播後呼叫 `SemanticsService.announce('主播目前未開播')`，公告雖開始但可能立刻被後續 semantics／焦點事件中斷，只聽到第一個字。

因此穩定策略是：

- VoiceOver 聚焦卡片時就直接知道未開播狀態。
- 不要求點兩下才取得關鍵狀態資訊。
- 非 VoiceOver 模式仍可保留視覺 Toast。

穩定修正：

```text
0c29eaca1473485ee8781657bbb7aca5bce18bdd
```

---

## 13. 「一滑一整條」與圖片降噪必須一起驗收

外層完整 `Semantics` 不是全部；共用圖片、Badge、Icon 等子元件也不能重新暴露無意義語義。

以下都屬 regression：

- 一支影片先讀「圖片」再讀完整影片卡。
- 一則評論前面多出頭像焦點。
- 一條彈幕被拆成名字、內容、貼圖、時間多個焦點。
- 播放器按鈕同時被讀成 icon 與按鈕兩次。
- 同一個表情／貼圖需要滑兩次才能操作。
- rebuild 後焦點跳回列表第一項。

---

## 14. 上游同步後快速驗收

除 `ACCESSIBILITY_MAINTENANCE.md` 外，至少抽查：

### 一般列表

- [ ] 首頁影片一滑一整條。
- [ ] 搜尋、UP 頁、相關影片、觀看紀錄、稍後再看語義完整。
- [ ] 主評論與樓中樓一滑一整條，時間在最後。
- [ ] 長列表三指翻頁仍正常。
- [ ] 沒有大量無意義圖片／Icon 焦點。

### 貼圖／表情

- [ ] 一般表情有名稱、可插入、有回饋。
- [ ] 直播貼圖有名稱／fallback，可插入或直接送出。
- [ ] 貼圖 Grid viewport 跟焦點同步。
- [ ] 分組 Tab 可朗讀、可點兩下，沒有被 `excludeSemantics` 吃掉。

### 播放器

- [ ] 進度條可讀目前時間／總時長／百分比並 ±10 秒調整。
- [ ] 播放／暫停名稱與即時狀態一致。
- [ ] Magic Tap 沒有退化。

### 直播

- [ ] 推薦卡一滑一個直播。
- [ ] 一條彈幕一個完整焦點，回覆與貼圖朗讀正確。
- [ ] 彈幕時間精確到秒、放最後、小時用「點」。
- [ ] 閱讀舊彈幕時新訊息不搶焦點。
- [ ] 焦點在直播頁任何主要控制時三指仍可翻聊天室。
- [ ] 三指向下往舊、三指向上往新。
- [ ] 最舊端再向下只提示最舊；最新端再向上更新／刷新。
- [ ] 刷新有語音回饋且播放器不中斷。
- [ ] 「回到底部」對 VoiceOver 可用。

### 觀看紀錄直播

- [ ] 已下播直播卡片聚焦時直接朗讀「主播目前未開播」。
- [ ] 未開播項目不再提示「點兩下繼續觀看」。
- [ ] 正在直播的紀錄仍可正常開啟。

---

## 15. 維護判斷原則

同步 PiliPlus 時不要以「官方程式碼為主，所以把 fork 的 widget 整份刪掉」處理無障礙差異。

正確方式：

1. 先理解上游新功能與 bug fix。
2. 找出 Accessibilibili 已實機驗證的使用者體驗。
3. 在上游新結構中重新套回同等語義、焦點與操作能力。
4. 不盲目覆蓋上游，也不因重構而放棄成熟無障礙行為。
5. 編譯成功後仍要做 VoiceOver 實機驗收；**能編譯不等於無障礙通過。**

這份稽核的目的不是追求「跟官方不同越多越好」，而是把已經真正改善 VoiceOver 日常操作的差異留下可驗收規格。未來 Hermes／其他維護工具在同步上游時，應以這些穩定行為為保護目標。

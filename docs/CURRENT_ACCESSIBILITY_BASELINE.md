# Accessibilibili 目前無障礙穩定基準

這份文件記錄目前已由 iPhone VoiceOver 實機驗證通過、可作為後續開發與同步 Pili Plus 上游版本時的回歸判定基準。

## 目前穩定點

- 日期：2026-09-11
- 分支：`main`
- **已驗證 App 程式碼基準 commit：`fc8a520ce92833c19b43741c387a9cb45e5889ec`**
- 本輪修正：控制中心／通知中心提前交接播放控制、播放頁進度列同步 VoiceOver 時間值（PR #3，修正 commit `3bb3f19`）。

本文件之後可能會有純文件 commit，因此 `main` HEAD 不一定等於上面的 SHA；判斷 App 行為時，以 `fc8a520c` 的程式碼狀態為本輪穩定基準。

除非後續版本完成新一輪 VoiceOver 實機驗證，否則遇到回歸應優先與此基準比較。

## 開發與驗證流程

使用者已明確持續授權直接提交及合併至 main，不必逐次詢問；除非有獨立測試需求，不另外建立 PR。開發環境無法執行的編譯與實機測試，由 Hermes 編譯 IPA、使用者在 iPhone 上驗證。只有使用者回報測試通過後，才更新已驗證穩定基準；程式碼提交本身不代表已實測。

## 本輪實機確認通過

2026-09-11 使用者回報 `fc8a520` 實測通過，確認左右滑評論明顯比 5669 順暢；此版本同時保留大量評論跨頁連續閱讀修復，作為目前評論無障礙穩定基準。

2026-09-11 使用者回報大量評論連續閱讀修復實測通過，確認評論跨頁沒有再出現讀到一半卡住、必須往左退再往右滑的問題；既有已驗證項目繼續保留，不表示本次重新執行了所有歷史測試。

2026-09-10 使用者回報本次修改「完全成功」，確認控制中心／通知中心播放控制與播放頁進度同步修復通過；同日亦實機確認首頁推薦、動態、觀看紀錄的 VoiceOver 三指邊界刷新與載入更多通過；既有已驗證項目繼續保留，不表示本次重新執行了所有歷史測試。

- 從影片播放頁直接拉下控制中心或通知中心，系統可接管雙指雙擊播放／暫停，控制中心播放／暫停控制可用。
- 播放頁進度列的 VoiceOver 時間與百分比隨影片進度同步，保留上下滑調整進度。

以下行為都屬於「不可因同步上游或重構而退步」的基準：

- 影片開始播放時，**不能中途截斷 VoiceOver 正在朗讀的語音**；影片聲音與旁白可以同時存在。
- 背景播放開啟時，播放中的影片退到主畫面或鎖屏後仍可播放。
- 播放中退背景後，可在背景暫停並再次播放。
- **前景先暫停，再退到主畫面／鎖屏，也能用 VoiceOver Magic Tap（雙指雙擊）重新播放。**
- 省電版 paused-first 背景方案已實測：退背景後等待 **10 秒**與 **1 分鐘**，仍可繼續播放。
- 回到 App 後 VoiceOver 可以正常朗讀，沒有因背景播放修正造成旁白被切斷。
- 動態投票選項可由 VoiceOver 正確辨識、朗讀選取狀態並操作。
- 投票建立頁的「顯示投票比例」與「匿名投票」可朗讀勾選狀態，且不再被 VoiceOver 誤報為「已變暗」。
- 影片收藏面板中，每個收藏夾只形成一個 VoiceOver 操作節點；名稱、內容數量、公開／私密資訊與勾選狀態會合併朗讀，雙擊整列即可切換。
- 影片投幣面板中，硬幣餘額可正常朗讀；「同時點讚」會朗讀已勾選／未勾選。
- 原創影片可由 VoiceOver 直接找到「投1枚硬幣」與「投2枚硬幣」兩個按鈕；已實機確認雙擊「投2枚硬幣」可一次正常投出 2 枚。
- 轉載／非原創影片維持 Bilibili 原有限制，只提供最多 1 枚硬幣的投幣額度。
- 動態的 VoiceOver「造訪使用者」：普通已關注 UP 直接進會員頁；訂閱 UGC 合集的特殊動態也能進入真正 UP 主頁。
- 評論／回覆、連續閱讀、首頁分頁、底部導航、影視卡片與既有富文字無障礙規則仍應維持各專項基準文件中的實機成功行為。
- 影片頁的「顯示彈幕」會讀成「顯示彈幕，已開啟」或「顯示彈幕，已關閉」，不再讀出「變暗」或多餘的切換按鈕描述。
- 影片頁的「更多選項」只朗讀一次，雙擊可開啟包含快取等較少使用功能的選單。
- 影片頁的「保存到相簿」可找到並操作；實機已確認保存後影片時長完整且有聲音。
- 發表彈幕的預設顏色與 VIP 彩色彈幕可由 VoiceOver 朗讀名稱及選取狀態；自訂顏色可朗讀色碼並操作。
- 發表彈幕的清除輸入按鈕會朗讀「清除彈幕文字」，不再誤讀為「關閉按鈕」；發送按鈕維持可朗讀。
- 首頁推薦、動態、觀看紀錄支援 VoiceOver 三指邊界操作：**三指向下滑是往回翻頁／往列表頂端移動，到達頂端後再次向下滑會重新整理**；**三指向上滑是往下一頁，到達底端後再次向上滑會載入更多**。三個頁面方向一致，不得反轉。
- 三指觸發重新整理或載入更多時，VoiceOver 會朗讀進行中、完成、失敗或「沒有更多內容」等狀態；一般自動預載不額外插入旁白。
- 動態頁單指滑動可跨過後續資料批次，不會在末端偶爾無法翻頁、跳回頂端或漏掉內容。
- 含附圖的評論或樓中樓長按選單提供「分享評論圖片」；單張直接分享，多張可選擇圖片，分享內容只包含原始附圖。

## 彈幕、動態與評論附圖分享基準

重點檔案：

```text
lib/pages/video/send_danmaku/view.dart
lib/pages/dynamics_tab/view.dart
lib/pages/video/reply/widgets/reply_item_grpc.dart
lib/utils/image_utils.dart
```

### 發表彈幕

- 每個色塊必須是單一、可操作的 VoiceOver 按鈕，朗讀顏色名稱及「已選取／未選取」。
- 自訂顏色入口朗讀「自訂彈幕顏色」；自訂色值會朗讀 6 位色碼；VIP 的透明色塊必須朗讀「彩色彈幕」。
- 清除鍵固定朗讀「清除彈幕文字」，不得沿用素材圖示的「關閉」語義；送出鍵仍朗讀「發送」。

### 動態翻頁

- 動態清單預先建立後續內容並在接近尾端時載入下一批，VoiceOver 單指滑動不可因 lazy layout 而停在最後一則。
- 新增資料、刪除動態或切換分類後，項目以動態 ID 保持節點身份，焦點與畫面不得跳回頂端。
- 清單與瀑布流都必須保留此行為。
- 三指向下滑回到頂端後再次向下滑可重新整理目前動態分類，三指向上滑到底後再次向上滑可載入下一批；方向不可與手勢相反。

### 原始評論附圖分享

- 只有 `content.pictures` 非空的評論／樓中樓長按選單顯示「分享評論圖片」。
- 單張直接開啟系統分享；多張先以「第 n 張圖片」選擇，取消不可分享任何檔案。
- 分享檔案必須是 `imgSrc` 的原始附圖，不能是含有評論文字、頭像或 QR code 的評論截圖。
- 既有「保存評論」保留；下載或使用者取消分享後，loading 遮罩必須關閉。
## iOS 影片音訊與背景播放基準

播放相關修改必須同時保住兩件事：

1. **VoiceOver 與影片音訊共存。** 前景播放不能搶走或掐斷 VoiceOver 語音。
2. **系統背景媒體控制可用。** 主畫面、鎖屏與 VoiceOver Magic Tap 必須能控制目前影片。

相關核心檔案包括：

```text
lib/services/audio_session.dart
lib/services/audio_handler.dart
lib/plugin/pl_player/controller.dart
packages/flutter_volume_controller/
packages/media_kit_libs_ios_video/ios/Classes/MediaKitLibsIosVideoPlugin.swift
ios/Runner/Info.plist
```

### 控制中心／通知中心與進度同步

- 不可只等 didEnterBackground 才交接：UIScene.willDeactivateNotification 與 Flutter inactive 都必須涵蓋，舊 iOS 使用 willResignActiveNotification。
- 回到 didActivate／didBecomeActive／resumed 才恢復前景 mixWithOthers，保留起播旁白共存與背景備援。
- 共用 `lib/common/widgets/progress_bar/audio_video_progress_bar.dart` 更新 progress、total、onSeek 與拖曳位置時，必須同步標記 semantics 更新；只有 markNeedsPaint 不會刷新 VoiceOver 快取。
- 不新增每秒主動朗讀或焦點跳轉。
- 完整修改與後續回歸清單見 `docs/IOS_OVERLAY_PLAYBACK_FIX.md`。

### paused-first 背景恢復的目前方案

早期已確認「影片正在播放後退背景」本來就能建立有效的系統媒體狀態；真正困難的是：

```text
前景播放 → 前景暫停 → 退背景／鎖屏 → Magic Tap 播放
```

連續零音量 native audio bridge 可以解決，但長時間播放靜音音訊會增加耗電，因此背景播放子系統自 `0cd4b40` 起採用、在 `3fc0d65` 已驗證、並延續到本輪基準 的方案為：

- 只有「已暫停後交接至系統角色」的必要情況才啟動 native `AVAudioEngine + AVAudioPlayerNode`。
- 使用真實硬體 mixer format 建立零音量 PCM buffer。
- 只在系統角色交接轉場時播放約 **2 秒**，用來建立／維持 Now Playing 媒體所有權。
- 2 秒後完整停止 engine，不在整段背景暫停期間持續播放靜音音訊。
- 已實測 10 秒及 1 分鐘後仍可 Magic Tap 恢復。

後續更新若改動這段，至少要重新測：

- [ ] 前景播放 → 直接退背景 → 暫停 → 再播放。
- [ ] 前景播放 → 前景暫停 → 退主畫面 → 等 10 秒 → Magic Tap 播放。
- [ ] 前景播放 → 前景暫停 → 鎖屏 → 等 1 分鐘 → Magic Tap 播放。
- [ ] 背景播放期間鎖屏控制正常。
- [ ] 回到 App 後 VoiceOver 正常。
- [ ] 開始／恢復影片時不截斷 VoiceOver 正在說的句子。

完整背景音訊排查記錄另見 `docs/IOS_BACKGROUND_AUDIO.md` 與 `docs/PLAYBACK_AUDIO_HANDOFF.md
docs/DANMAKU_DYNAMIC_IMAGE_A11Y.md`。

## 動態「造訪使用者」基準

重點檔案：

```text
lib/pages/dynamics/widgets/dynamic_panel.dart
```

### 普通已關注 UP

`AUTHOR_TYPE_NORMAL` 必須維持最簡單、最快的原路徑：

```text
module_author.mid → /member?mid=<UID>
```

不要為普通已關注 UP 加入額外 API 查詢或快取層。

### 訂閱 UGC 合集的特殊動態

Bilibili 的 `AUTHOR_TYPE_UGC_SEASON` 動態中，`module_author.mid` 可能是影片 aid，而不是 UP 主 UID，因此不能直接當會員 UID 使用。

目前穩定基準採用已實機驗證成功的方式：

```text
UGC season aid
→ VideoHttp.videoIntro
→ response.owner.mid
→ /member?mid=<真正 UP 主 UID>
```

這條路徑可能比普通已關注 UP 稍慢，但已確認能正確進入發佈者頁面。

### 已撤回的合集快取實驗

下列三個 commit 曾嘗試使用 `seasonId → ownerMid` 持久化快取，以及優先呼叫訂閱合集 API：

```text
caf67d4dee23992bec1c5874b0267580c35c20ef  perf(a11y): cache subscribed UGC season owners
c05910dde5ae0900f65789b1247a4a41719adb95  perf(a11y): reuse UGC season owner cache
1dc1ab306a39b2b03b37e11fb110a55bf5563ae0  perf(a11y): prefer UGC season owner shortcut
```

實機使用感受沒有比既有路徑明顯更快，因此**這三個 commit 已從 `main` 撤回，不屬於目前穩定基準**。日後不要因看到這些歷史 commit 就自動重新套用。

## 動態投票穩定基準

`lib/pages/dynamics/widgets/vote.dart` 的每個投票選項、圖片投票與百分比選項都必須是單一可操作的 VoiceOver 節點。

朗讀內容應包含：

- 選項文字。
- 已選取／未選取狀態。
- 顯示比例時的百分比。
- 適當的「雙擊選擇／取消選擇」操作提示。

不能把圖片、勾選圖示、比例進度條、百分比 badge 與文字拆成一串重複焦點。

投票建立頁的「顯示投票比例」與「匿名投票」也必須各自是可切換且會朗讀狀態的控制項；外層 semantics 必須維持啟用狀態，不能再讓 VoiceOver 額外朗讀「已變暗」。

同步上游時，保留外層 `Semantics`、`enabled: true`、`selected/checked`、共用 `onTap` 與內層 `ExcludeSemantics` 的組合。

## 影片收藏面板穩定基準

重點檔案：

```text
lib/pages/fav_panel/view.dart
```

每個收藏夾的整列與右側 Checkbox **不能拆成兩個 VoiceOver 按鈕／焦點**。

目前基準做法：

- 外層 `Semantics` 把整個收藏夾合併成單一節點。
- `label` 朗讀收藏夾名稱。
- `value` 朗讀內容數量與公開／私密資訊。
- `checked` 提供已勾選／未勾選狀態。
- `onTap` 與視覺上的整列點擊共用同一切換邏輯。
- 內層 `ListTile`、圖示與 Checkbox 使用 `ExcludeSemantics`，避免重複焦點。

後續同步上游若收藏面板 UI 改版，仍要維持「一個收藏夾 = 一個 VoiceOver 操作節點」。

## 影片投幣面板穩定基準

重點檔案：

```text
lib/pages/video/pay_coins/view.dart
```

原版視覺上的投幣角色圖片實際承擔送出動作，但沒有按鈕語義，而且原創影片的 1／2 枚選擇依賴 PageView 橫向滑動，VoiceOver 使用者無法可靠知道或切換到 2 枚。

目前基準必須維持：

- 原創且尚有完整投幣額度的影片，VoiceOver 可直接左右滑找到兩個獨立按鈕：「投1枚硬幣」與「投2枚硬幣」。
- 雙擊「投1枚硬幣」直接投出 1 枚；雙擊「投2枚硬幣」直接投出 2 枚，不需要先操作視覺 PageView 或再找第二個確認按鈕。
- **「投2枚硬幣」已由 iPhone VoiceOver 實機驗證，可一次正常送出 2 枚硬幣。**
- 若影片已經投過 1 枚，剩餘額度只能再投 1 枚；2 枚選項不可誤導成仍可投 2 枚。
- 轉載／非原創影片依 Bilibili 原有限制最多只能投 1 枚，不應為了無障礙強行提供 2 枚操作。
- 餘額不足的投幣項目必須正確呈現停用狀態與提示。
- 硬幣餘額／已投硬幣資訊有獨立且清楚的 semantics，不依賴圖片猜測。
- 「同時點讚」是單一 checkbox semantics，會朗讀已勾選／未勾選且可雙擊切換。
- 關閉投幣面板的圖片也必須有明確的「關閉投幣」按鈕語義。
- 視覺使用者原本的 PageView、左右箭頭、橫向選 1／2 枚、投幣動畫與拖曳行為仍要保留；這些視覺控制不應額外形成重複的 VoiceOver 焦點。

## 首頁與底部導航基準

### 底部導航

`lib/pages/main/view.dart` 不要重新加入只有朗讀「導覽列」但沒有實際作用的外層焦點。VoiceOver 觸摸瀏覽底部時，應直接遇到真正可操作的首頁、動態、我的等分頁按鈕。

### 首頁頂部分頁

`lib/pages/home/view.dart` 在 VoiceOver／accessible navigation 模式下：

- 每個頂部分頁是獨立可操作的 semantics 節點。
- 能朗讀分頁名稱與 selected 狀態。
- `Semantics.onTap` 必須直接依該分頁 index 切換。
- VoiceOver 模式使用直接 index／`IndexedStack` 行為，不把 `TabBarView` 的非同步 page warp 當作切頁核心。
- 非無障礙模式仍可維持 Pili Plus 原本的滑動分頁體驗。

若修改首頁分頁，至少壓測推薦 ↔ 直播、番劇 ↔ 影視，以及直播 ↔ 影視等跨多頁切換，不能出現雙擊無反應或落到相鄰頁。

## 影視卡片基準

`lib/pages/pgc_index/widgets/pgc_card_v_pgc_index.dart` 的 VoiceOver 資訊順序應維持：

```text
片名 → 集數／狀態 → 追劇數 → 出品／獨家等角標 → 按鈕
```

整張作品卡以主要單一可操作節點呈現，雙擊開啟作品與既有長按行為不可被語義整理破壞。

## 既有無障礙專項規格

本文件是「目前整體穩定點」的最高層指標；下列專項文件中的既有規則仍然有效：

```text
docs/ACCESSIBILITY_MAINTENANCE.md
docs/VOICEOVER_SEMANTICS_BASELINE.md
docs/IOS_RICH_TEXT_VOICEOVER_BASELINE.md
docs/LIVE_ACCESSIBILITY_BASELINE.md
docs/VOICEOVER_CONTINUOUS_READING.md
docs/COMPOSER_DOCK.md
docs/COMPOSER_TOUCH_PRIORITY.md
docs/VIDEO_BUFFERING.md
docs/IOS_BACKGROUND_AUDIO.md
docs/PLAYBACK_AUDIO_HANDOFF.md
```

尤其不要因更新 Pili Plus 上游而退回：

- iOS 富文字圖片／表情在 VoiceOver 的正確朗讀與逐字瀏覽。
- 評論／樓中樓、發表評論與發表回覆控制項的可達性。
- 三指翻頁、VoiceOver 焦點與 viewport 同步。
- VoiceOver 連續閱讀。
- 播放緩衝優化。
- 首頁與動態等頁面的既有語義整理。

## 本輪重要 commits

以下重要修正都包含在目前已驗證 App 基準 `9a98521` 的 ancestry 中：

```text
f2ae922820e20ef8864afba60e451a4fa7c78505  fix(ios): preserve VoiceOver speech during playback
334d747e088f6b43712f46b9ac6d68750397cb2b  fix(a11y): expose poll selection state
cc667db9c824dc422bb3a34b47f1999e5d5b7a26  fix(a11y): trim redundant poll labels
6097c507ffcfda8ab4bac8b2c8cf2d19cc5224cd  fix(ios): preserve playback session during volume observation
a30dbbe67c37553e89c3d9e05eda97640df1819a  fix(ios): promote background playback for Magic Tap
3bc7523d5579a65719d5900c4edee6945e2db16d  Fix VoiceOver visit user for subscribed UGC seasons
1379558fc289fd14163a9710cb4e41c7370fc316  fix(ios): keep paused media resumable in background
b7392297bd52aecd3f7ce80382a15ddee9312208  fix(ios): use hardware audio format for pause bridge
0cd4b40f7982e4ccc2f87841e9c16a56bb2b52f2  fix(ios): prime paused background media without continuous silent audio
7a6fa83e1d3639057adf65339a269cfb1f56324f  fix(a11y): keep vote toggles enabled for VoiceOver
26c746bcbe0ee229bb81fd05d5e8c96ac502d3f5  fix(a11y): merge favorite folder controls
a31ac99b488eaf6bf4e76c5d17f02e9a09ff68d1  fix(a11y): expose coin controls to VoiceOver
3fc0d658b5f247c8dd919089cfa4efdea4a70e5d  fix(a11y): expose direct one and two coin actions
```

## 同步 Pili Plus 上游時的最低驗收

每次更新官方版本後，在把新版視為 Accessibilibili 新基準前，至少用 iPhone VoiceOver 確認：

- [ ] 首頁／動態／我的等主要頁面左右滑與觸摸瀏覽正常。
- [ ] 首頁頂部分頁切換穩定。
- [ ] 評論與回覆可找到、可操作。
- [ ] 連續閱讀沒有卡死或異常跳焦點。
- [ ] 動態投票可朗讀狀態並投票。
- [ ] 投票建立頁「顯示投票比例」與「匿名投票」會朗讀勾選狀態，且不會朗讀「已變暗」。
- [ ] 普通動態「造訪使用者」直接進正確 UP 主頁。
- [ ] UGC 合集動態「造訪使用者」能進真正 UP 主頁。
- [ ] 影片收藏面板每個收藏夾只停一次焦點，能朗讀勾選狀態並雙擊切換。
- [ ] 投幣面板能朗讀硬幣餘額與「同時點讚」狀態。
- [ ] 原創且可投 2 枚的影片能直接找到「投1枚硬幣」與「投2枚硬幣」兩個 VoiceOver 按鈕。
- [ ] 雙擊「投2枚硬幣」可一次正常投出 2 枚。
- [ ] 轉載／非原創影片不會錯誤提供超過 1 枚的可用投幣額度。
- [ ] 播放影片不切斷 VoiceOver。
- [ ] 播放中退背景仍可播放／暫停／恢復。
- [ ] 前景暫停後退背景，Magic Tap 仍可恢復。
- [ ] 回前景後 VoiceOver 正常。
- [ ] 播放頁直接拉下控制中心／通知中心，雙指雙擊可播放／暫停，控制中心按鈕可用。
- [ ] 播放頁進度列時間及百分比持續同步，上下滑仍可調整進度。

任何一項失敗，都應視為上游同步 regression，而不是直接覆蓋目前無障礙實作。

## 影片頁控制與保存到相簿基準

自 `17007d6` 起納入已實機確認的穩定基準：

- 「顯示彈幕」是單一 VoiceOver 控制項，狀態使用「已開啟／已關閉」值；雙擊可切換。
- 有文字的「更多選項」不重複朗讀，雙擊可開啟選單；選單內保留快取、稍後再看、筆記、封面及其他原有功能。
- 「保存到相簿」可由播放頁找到；保存目前影片分 P 後，已確認影片時長完整且有聲音。
- 保存流程的快取重用、音畫合成與下載完整性規格見 `docs/VIDEO_PHOTO_EXPORT.md`。

以上三項已由 iPhone VoiceOver 實機確認，後續同步 Pili Plus 上游時不得移除或改回未命名／重複朗讀的控制項。

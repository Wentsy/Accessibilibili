# Accessibilibili VoiceOver 語義基準

這份文件記錄 Accessibilibili 最核心的無障礙設計原則：**VoiceOver 應以穩定、完整、可操作的內容單位閱讀介面，而不是被 Flutter 畫面上的 Text、Icon、Image、Badge 或裝飾子元件切碎。**

這套行為不是 PiliPlus 官方版本原本就完整具備的。未來同步 PiliPlus 上游、升級 Flutter 或重構 widget 時，應保留本文件描述的**使用者可觀察行為**。

目前完整實機基準請同時參考：

```text
docs/ACCESSIBILITY_MAINTENANCE.md
docs/IOS_RICH_TEXT_VOICEOVER_BASELINE.md
docs/LIVE_ACCESSIBILITY_BASELINE.md
```

## 第一原則：一滑就是一個完整內容單位

VoiceOver 左右滑動時，使用者應以「影片」、「評論」、「直播彈幕」等內容實體為單位，而不是以畫面元件為單位。

### 影片卡

理想朗讀：

```text
影片標題，UP 主，時長／觀看進度，播放量，彈幕量，發布時間
```

時間等次要資訊放在後段，不應先搶過標題。

不應退化成：

```text
第一滑：12 分 34 秒
第二滑：影片標題
第三滑：UP 主
第四滑：播放量
第五滑：9 月 2 日
```

實作上通常由最外層 `Semantics` 代表整張卡；無獨立操作價值的封面、角標、時長 Badge、播放圖示等不應各自成為 VoiceOver 焦點。點讚、分享、稍後再看、造訪 UP 主、更多等附加操作，優先以 `CustomSemanticsAction` 提供，而不是拆成大量焦點。

## 評論：一則評論＝一個主要語義節點

VoiceOver 聚焦一則評論時，應一次取得主要資訊，例如：

```text
評論者，身份／必要狀態，評論內容，讚數，回覆數，評論時間
```

評論時間放最後，例如：

```text
3 小時前評論
9 月 2 日評論
```

主評論與樓中樓都應盡量共用一致策略，不應出現：

- 有些評論一滑完整、有些被拆成兩三滑。
- 第一滑只讀評論者，下一滑才讀內容。
- 讚數、回覆數、時間各自變成沒有必要的獨立焦點。
- 樓中樓和主評論的語義順序完全不同。

共用評論語義重要入口：

```text
lib/common/a11y/reply_semantics.dart
```

外層節點應負責完整 label、必要狀態、評論時間、點讚／點踩、自訂操作以及 VoiceOver focus 與真實 viewport 的同步。

## 應套用「完整內容單位」的頁面

至少包括：

- 首頁 Web 推薦。
- 首頁 App 推薦。
- 搜尋結果影片。
- UP 個人頁影片。
- 相關影片／推薦影片。
- 觀看紀錄。
- 稍後再看。
- 主評論區。
- 樓中樓評論。
- 直播推薦卡。
- 直播聊天室彈幕。
- 其他「一列／一卡代表一個內容實體」的頁面。

## 與 viewport／翻頁機制的關係

「一滑一整條」和焦點／viewport 同步、三指翻頁、lazy list semantics 建立是同一套使用體驗。

必須同時維持：

1. 左右滑一次移動到下一個完整內容節點。
2. VoiceOver 焦點移動時，實際畫面跟著移動。
3. 接近 lazy list 邊界時提前建立後續項目，避免邊界音後無法繼續。
4. 三指翻頁後，新畫面內容仍是完整語義節點。
5. 分頁 append/rebuild 後不因焦點恢復跳回第一項。

上游若修改以下區域，需要重新驗證：

```text
Semantics
ExcludeSemantics
ListView
GridView
SliverList
SliverGrid
ScrollView
影片卡 widget
評論 widget
直播聊天室 widget
列表 item widget
```

## 上游同步時的高風險訊號

以下任何一項都視為無障礙 regression：

- 一支影片需要滑多次才能把標題與基本資訊聽完整。
- VoiceOver 先讀時長／角標，再讀標題。
- 封面、時長 Badge、播放圖示各自成焦點。
- 評論者與評論內容被拆成不同焦點。
- 樓中樓語義順序與主評論不一致。
- 一條直播彈幕被拆成使用者、文字、貼圖、時間多個焦點。
- 左右滑需要穿過大量裝飾元素。
- 同一內容被重複朗讀。
- 自訂操作消失，只剩視覺按鈕或長按可用。
- rebuild 後 VoiceOver 焦點跳回列表第一項。

## 快速驗收

### 首頁／影片列表

- [ ] 一次左右滑移到下一支影片。
- [ ] 每支影片一次朗讀標題與主要資訊。
- [ ] 時長／播放量／時間等不各自形成多餘焦點。
- [ ] 發布時間位於整條資訊後段。
- [ ] 實際 viewport 跟著 VoiceOver 焦點移動。
- [ ] 搜尋、UP 個人頁、觀看紀錄、稍後再看、相關影片抽查一致。

### 評論區

- [ ] 主評論一次滑動聚焦一整則。
- [ ] 評論者與內容不拆成兩次滑動。
- [ ] 讚數、回覆數、時間不各自形成多餘焦點。
- [ ] 評論時間在最後。
- [ ] 樓中樓和主評論閱讀方式一致。
- [ ] 左右連續瀏覽不觸礁、不跳回第一則。

## 全域貼圖／表情 VoiceOver 基準

貼圖相關功能必須先分清楚兩種完全不同的場景：

1. **貼圖選擇面板／Grid／Tab**：使用者在挑選要插入或送出的貼圖。
2. **focused rich-text editor 內的 inline 圖片表情**：貼圖已經存在文字輸入欄位中，使用者要逐字讀、移游標、繼續打字、跳頭尾、刪除。

這兩個場景不能用同一套 implementation 取代彼此。

## A. 貼圖選擇面板／Grid

### 每張貼圖是一個穩定操作節點

- 貼圖不能只暴露圖片，也不能只念「圖片」或「按鈕」。
- 每張可插入／可直接送出的貼圖應是一個穩定 VoiceOver 節點。
- 優先使用 API 提供的 emoji／alias／文字名稱。
- 沒有可靠名稱時至少朗讀「貼圖」。
- 面板內 label 可以用自然功能描述，例如「doge 貼圖」；這條**只適用於 picker／grid，不是 focused editor 的 inline attachment 命名規則**。

### 操作提示與實際行為一致

- 插入型：提示「點兩下插入這個貼圖」。
- 直接送出型：提示「點兩下送出這個貼圖」。
- VoiceOver `onTap` 與視覺點擊共用同一 callback。
- 插入／送出後可以提供簡短回饋，但不要讓公告破壞後續焦點或編輯狀態。

### Grid viewport 同步

- VoiceOver 左右移動貼圖焦點時，真實 Grid viewport 跟著移動。
- 不讓 VoiceOver 焦點跑到畫面外，而 Grid 停在舊位置。
- lazy grid 更新時焦點不跳回第一張。

### 貼圖包／分類 Tab

- 分組 Tab 可朗讀、可點兩下切換。
- 有名稱用真正名稱；沒有可用「貼圖包第 N 組」。
- 分組封面不額外形成重複焦點。
- 不要用會吃掉 TabBar 操作的 `excludeSemantics: true`。

### 貼圖入口

- icon-only 的貼圖入口不能只念「按鈕」或圖像描述。
- 名稱描述下一步功能，例如「表情與貼圖」。
- 面板開啟後如果同一按鈕變成返回鍵盤，名稱也應改成「鍵盤」等下一步操作。

直播貼圖 `lib/pages/live_emote/view.dart` 已做過實機驗證；不要再把它記成「已 revert／尚未完成」。

## B. focused editor 內的 inline 圖片表情

**這一節以 `docs/IOS_RICH_TEXT_VOICEOVER_BASELINE.md` 為唯一完整技術基準。**

目前 iOS 評論／回覆輸入欄位已經實機確認：要讓 VoiceOver Character rotor 真正逐字讀出 `[doge]`、`[笑哭]` 等 inline image emote，focused editor 本身必須進入真正的 UIKit rich-text system。

目前架構：

```text
UITextView + NSTextAttachment
```

核心規則：

- 一張圖片表情＝一個 UTF-16 selection slot。
- underlying focused text buffer 使用一個 U+FFFC。
- attachment `accessibilityLabel` 保留原 token 名稱，例如 `[doge]`。
- **不要把 `[doge]` 在 focused editor 中展開成多個字元。**
- 不要為了好聽把 bracket 拿掉；Character rotor 的已驗證名稱就是 `[doge]` 這類 token。
- 不要在名稱後人工補「表情」；系統若需要會自行表達 attachment 類型。
- Dart `RichTextEditingController` 保存 raw token，發表時還原 Bilibili token。
- selection offset 維持一對一，不建立第二套 token offset mapping。

驗證範例：

```text
好耶 [doge] 啊 [笑哭]
```

VoiceOver 轉輪切「字元」後，必須可逐格走過：

```text
好
耶
[doge]
啊
[笑哭]
```

不能只念「附件」、不能跳過貼圖、不能拆成左中括號／d／o／g／e／右中括號。

### 鍵盤與游標操作

- 表情面板 read-only 狀態後，回輸入欄位雙擊能重新展開鍵盤。
- 有 attachment 時，雙擊仍能快速在文字開頭／結尾切換。
- attachment 觸發邊界跳轉後，明確朗讀「插入點在開頭／結尾」。
- 一次 Backspace 整顆刪除一張 attachment。
- attachment 原生刪除回饋若亂念第一個字或鍵盤預測內容，只在 attachment deletion 這個窄範圍補「刪除 [名稱]」；普通字元刪除仍尊重使用者自己的 VoiceOver 輸入回饋。

目前完整實機基準：

```text
2a14e69b480dabb5d6bbf94bb17e8677a299f9c2
```

### 已知不可當等價替代的方案

以下方向已實機證明不足以取代真正 native rich editor：

- 單純換 U+FFFC placeholder。
- Dart character cursor callback + announcement。
- hook `textInRange:`。
- 只改 `accessibilityAttributedValue`。
- `NSAccessibilityCustomTextAttribute`。
- 對 private `FlutterTextInputView` 假造 `attributedText`。
- 不真正參與編輯的 accessibility mirror `UITextView`。

未來除非 iOS／Flutter 行為有明確改變並重新實機驗證，否則不要回退到上述方案。

## 貼圖全域驗收清單

### picker／grid

- [ ] 貼圖入口有明確名稱。
- [ ] 左右滑可逐張找到貼圖。
- [ ] 每張貼圖有名稱，缺資料至少有 fallback。
- [ ] 插入／送出提示和實際行為一致。
- [ ] Grid viewport 跟著焦點移動。
- [ ] lazy grid 更新焦點不跳第一張。
- [ ] 分類 Tab 可朗讀、可點兩下切換。
- [ ] 分組圖片不造成重複焦點。

### focused editor

- [ ] 插入 `[doge]` 後仍可繼續輸入一般文字。
- [ ] Character rotor 可逐格讀出 `[doge]`。
- [ ] 一張貼圖一個 selection slot。
- [ ] 表情面板後雙擊可恢復鍵盤。
- [ ] 有貼圖仍可雙擊跳文字開頭／結尾。
- [ ] 跳轉後朗讀插入點在開頭／結尾。
- [ ] 一次 Backspace 只刪一張貼圖。
- [ ] 刪貼圖穩定朗讀「刪除 [名稱]」，不亂念其他內容。
- [ ] 普通字元刪除維持系統原生回饋。
- [ ] 發表內容仍是 server raw token，不是裸 U+FFFC。

## 直播彈幕也是完整內容單位

直播聊天室雖然是即時列表，語義原則不變：**一條彈幕＝一個完整 VoiceOver node。**

完整 label 應包含：

```text
發送者／回覆關係，訊息內容／貼圖文字，發送時間
```

例如：

```text
小明 說：晚上好，今天1點23分45秒發送
小明 回覆 小華：收到，今天1點24分02秒發送
```

直播彈幕時間：

- 使用可靠 UNIX 秒級 `ts`。
- 精確到秒。
- 放在整條資訊最後。
- 小時用「點」而不是「時」，避免高語速黏音。
- 無效時間直接省略，不猜測。

即時列表還要維持：

- VoiceOver 閱讀舊訊息時，新訊息不搶焦點。
- 新訊息可排隊，不因 rebuild 把焦點跳回第一條。
- 三指翻頁、單指閱讀與「回到底部」合理回到最新內容。

完整直播規格見 `docs/LIVE_ACCESSIBILITY_BASELINE.md`。

## 狀態資訊優先放進既有語義

如果某個狀態在使用者聚焦內容時就已經知道，應優先放進該內容完整 `Semantics.label`，不要要求使用者先點擊失敗，再靠 Toast／announce 補救。

例如觀看紀錄中的未開播直播：

```text
直播標題，主播名稱，昨天看過，主播目前未開播
```

規則：

- `business == 'live' && liveStatus != 1` 時，把「主播目前未開播」放在觀看紀錄卡 label 最後。
- 既然無法繼續觀看，hint 不再說「點兩下繼續觀看」。
- VoiceOver 不依賴點擊後 announce；這類公告可能被後續 semantics／焦點事件中斷。
- 非 VoiceOver 模式仍可保留視覺 Toast。

這個原則可推廣到其他「點了其實不能做」的已知狀態：**如果狀態在聚焦時已確定，就讓使用者第一次聽到項目時直接知道。**

## 維護判斷原則

上游重寫影片卡、評論、直播彈幕、貼圖面板或富文字編輯器時：

1. 保留上游新功能與 bug fix。
2. 找出新的邏輯內容單位。
3. 重新套回完整 semantics／native accessibility 行為。
4. 不讓無操作價值子元件搶焦點。
5. 保留 custom actions、viewport 同步與分頁 identity。
6. iOS rich editor 必須額外跑 `docs/IOS_RICH_TEXT_VOICEOVER_BASELINE.md` 完整實機測試。
7. 不只看「能編譯」；VoiceOver 實際使用方式才是驗收標準。

最重要的是保留使用者體驗，而不是機械保留某段舊程式；但在沒有新的實機證據前，不要移除已經驗證成功的原生無障礙架構。
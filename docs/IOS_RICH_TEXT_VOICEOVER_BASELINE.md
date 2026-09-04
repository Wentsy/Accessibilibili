# iOS 富文字編輯器 VoiceOver 基準

這份文件記錄 Accessibilibili 在 iOS 上，針對評論／回覆輸入欄位中的圖片表情、貼圖與 VoiceOver 所建立的**實機驗證基準**。

目前完整驗證基準 commit：

```text
2a14e69b480dabb5d6bbf94bb17e8677a299f9c2
```

這套行為經過多輪 iPhone + VoiceOver 實機測試後確認可用。未來同步 PiliPlus 上游、升級 Flutter／iOS、重構文字輸入元件時，應把本文件當成不可退化的無障礙規格，而不是把目前實作視為可任意替換的細節。

## 核心 invariant：一張圖片表情＝一個編輯槽

最重要的規則：

> **一張 inline image emote / sticker 必須永遠只佔一個 UTF-16 編輯位置。**

目前使用 U+FFFC（Object Replacement Character）作為文字 buffer 中的單一佔位字元，並在 iOS 原生富文字編輯器中對應真正的 `NSTextAttachment`。

例如：

```text
好 | 耶 | [doge] | 啊 | [笑哭]
```

在 selection／cursor 座標中必須等價於五個邏輯位置，不可以把 `[doge]` 展開成六個字元後再建立第二套 offset mapping。

這個 invariant 同時保證：

- 字元轉輪可以一格一格移動。
- 一張貼圖只需要一次 Backspace。
- selection offset 與 Flutter `RichTextEditingController` 保持一對一。
- 插入點不會因 `[doge]` 等 server token 長度不同而漂移。
- 發表時仍可由 Dart rich-text model 還原原始 token，例如 `[doge]`。

## 目前正確架構：真正的原生 UITextView

對 iOS 評論／回覆富文字輸入欄位，現在使用真正的原生：

```text
UITextView + NSTextAttachment
```

而不是只在 Flutter semantics 上模擬附件。

主要檔案：

```text
ios/Runner/AppDelegate.swift
lib/common/widgets/flutter/text_field/ios_native_rich_text_field.dart
lib/common/widgets/flutter/text_field/controller.dart
lib/pages/video/reply_new/view.dart
```

架構原則：

1. iOS 畫面上的實際編輯器是 `UITextView`。
2. 每張圖片表情在 `UITextView` 的 attributed string 中是真正的 `NSTextAttachment`。
3. attachment 的 `accessibilityLabel` 使用原 token 名稱，例如 `[doge]`、`[笑哭]`。
4. 文字 buffer 仍只有一個 U+FFFC，不把 token 展開進 focused editor。
5. Dart 端 `RichTextEditingController` 繼續作為 rich item / raw token 的資料來源。
6. native 文字與 selection 變化透過 MethodChannel 回 Dart，轉成既有 `TextEditingDelta`，再走 `syncRichText()`。
7. 發表 API 不應直接送 U+FFFC，而是維持原本 rich-text model 的 raw token。

## VoiceOver 逐字瀏覽的驗證行為

這是本次改造最重要、也最容易被未來重構破壞的部分。

假設輸入：

```text
好耶 [doge] 啊 [笑哭]
```

### 外層／整個編輯欄位

VoiceOver 聚焦整個欄位時，可以朗讀帶名稱的完整內容，例如：

```text
好耶 [doge] 啊 [笑哭]
```

### 轉輪切到「字元」後

逐字移動時必須可以依序走過：

```text
好
耶
[doge]
啊
[笑哭]
```

貼圖不能只剩「附件」，也不能被拆成：

```text
左中括號
d
o
g
e
右中括號
```

更不能跳過貼圖。

VoiceOver 可能依系統語音規則在 attachment 名稱後補充「附件」，但應保留真正名稱，例如 `[doge]`。

## 編輯狀態與鍵盤恢復

表情面板開啟時，輸入欄位可能暫時處於 read-only 狀態；使用 VoiceOver 回到欄位並雙擊時，必須能重新切回鍵盤並繼續輸入。

目前需要同時維持：

- read-only attachment／UITextView 的 `accessibilityActivate()` 能通知 Flutter 切回 keyboard panel。
- Dart 把 `readOnly=false` 與 `FocusNode.hasFocus` 同步回 native。
- native 在解除 read-only 後主動 `becomeFirstResponder()`。
- 不可以只依賴 Flutter `FocusNode` 再次變化；FocusNode 可能原本就保持 focus，listener 不會重新觸發。

驗收案例：

1. 輸入「好耶」。
2. 開啟表情面板。
3. 插入 `[doge]`。
4. VoiceOver 左右滑回輸入欄位。
5. 雙擊。
6. 鍵盤必須重新展開。
7. 能在 `[doge]` 後繼續輸入「啊」。

## VoiceOver 雙擊快速跳開頭／結尾

原生 attachment 存在時，VoiceOver 的 activation 有時會落在 `NSTextAttachment`，而不是外層 `UITextView`。

因此目前同時讓：

- `UITextView.accessibilityActivate()`
- 自訂 `NSTextAttachment.accessibilityActivate()`

都能轉發到同一套 cursor boundary 行為。

目前驗證規則：

- 插入點在開頭時雙擊 → 跳到結尾。
- 插入點在其他位置時雙擊 → 跳到開頭。
- attachment 觸發跳轉時，額外用 VoiceOver announcement 明確報：
  - `插入點在開頭`
  - `插入點在結尾`

沒有 attachment、系統本身已能正確播報時，不應重複額外 announcement。

## 刪除貼圖的基準

一張圖片表情必須像普通字元一樣，一次 Backspace 整顆刪除。

資料路徑仍維持原生：

```text
UITextView deleteBackward
→ 一個 U+FFFC deletion
→ Dart TextEditingDeltaDeletion
→ RichTextEditingController.syncRichText()
→ 對應 RichTextItem 移除
```

不能為了刪除貼圖另外建立多字元 token offset。

### VoiceOver 刪除回饋例外

實機發現 VoiceOver 對 `NSTextAttachment` 的原生刪除回饋不穩定，可能錯念：

- 輸入內容第一個字。
- 鍵盤預測／推薦輸入內容。
- 其他與剛刪除貼圖無關的文字。

因此只有在 `deleteBackward()` 確認游標前一格是 attachment 時，才做窄範圍修正：

1. 先讀取 attachment `accessibilityLabel`。
2. 仍呼叫 `super.deleteBackward()`，保留原生編輯／delta 流程。
3. VoiceOver 開啟時送出不排隊的 announcement，例如：

```text
刪除 [doge]
```

普通文字、英文字母、中文與標點的刪除完全不攔截，繼續尊重每位使用者自己的 VoiceOver 輸入回饋設定。

## 不要回退到以下已證明失敗的方案

本專案已實機驗證以下方向不足以讓 VoiceOver「字元」轉輪正確朗讀圖片表情名稱。未來不要因上游重構而重新走同一條路，除非 iOS／Flutter 行為已有明確改變並重新實機驗證。

### 1. 只換 U+FFFC 成一般 Unicode 字元

曾用單字元替代 U+FFFC，可維持 offset，但 VoiceOver 只會把它當普通字元，無法得到真正圖片表情名稱。

### 2. Dart cursor callback + Semantics announcement

`onMoveCursorForwardByCharacter`／backward 等 Flutter callback 無法控制 iOS native VoiceOver Character rotor 的實際逐字朗讀。

### 3. hook `textInRange:`

在 private Flutter text input path 替換 `textInRange:` 回傳內容，沒有改變 Character rotor 對 inline attachment 的朗讀。

### 4. 只改 `accessibilityAttributedValue`

在 `TextInputSemanticsObject` 上提供 attributed string／attachment metadata，可以影響部分整體朗讀，但不能穩定讓 Character rotor 取得 `[doge]` 名稱。

### 5. `NSAccessibilityCustomTextAttribute`

Custom text attribute 沒有解決 Character rotor；VoiceOver 仍可能只念「附件」。

### 6. 對 private `FlutterTextInputView` 假造 `attributedText`

即使回傳同長度 attributed string + `NSTextAttachment`，只要真正參與編輯的 native text system 仍是 plain Flutter text input，VoiceOver Character rotor 仍不會可靠採用 attachment 名稱。

### 7. accessibility mirror UITextView

把一個不真正參與編輯的 `UITextView` 當 accessibility mirror，也不足以取代實際 text input system。

**結論：目前成功的關鍵不是「讓 VoiceOver 相信它是 attachment」，而是讓 focused editor 本身真的成為 UIKit rich-text editor。**

## 上游更新時不可破壞的檔案與行為

若上游修改以下任何區域，必須重新跑本文件完整驗收：

```text
ios/Runner/AppDelegate.swift
lib/common/widgets/flutter/text_field/ios_native_rich_text_field.dart
lib/common/widgets/flutter/text_field/controller.dart
lib/pages/video/reply_new/view.dart
表情選擇／插入相關 callback
PanelType.keyboard / readOnly / FocusNode 切換邏輯
```

特別警告：

- 不要因 upstream TextField 重構而直接把 iOS 分支換回普通 Flutter `RichTextField`。
- 不要把 attachment raw token 展開到 focused editor。
- 不要另外建立「顯示 offset」和「真實 offset」兩套 selection 座標。
- 不要移除 `NSTextAttachment.accessibilityLabel`。
- 不要讓 attachment activation 吃掉「切回鍵盤」或「跳開頭／結尾」行為。
- 不要把貼圖刪除 announcement 套到普通字元。

## 實機快速驗收清單

使用 iPhone VoiceOver，至少測以下流程：

- [ ] 輸入一般文字，例如「好耶」。
- [ ] 插入 `[doge]`。
- [ ] 在貼圖後繼續輸入「啊」。
- [ ] 再插入第二張不同貼圖，例如 `[笑哭]`。
- [ ] 外層聚焦輸入欄位時能取得完整內容與貼圖名稱。
- [ ] 轉輪切「字元」，可依序走過「好 → 耶 → [doge] → 啊 → [笑哭]」。
- [ ] 每張貼圖只佔一個插入位置。
- [ ] 表情面板開啟後，回到輸入欄位雙擊能重新展開鍵盤。
- [ ] 有貼圖時仍能雙擊快速在文字開頭／結尾切換。
- [ ] attachment 路徑跳轉後會朗讀「插入點在開頭／結尾」。
- [ ] 一次 Backspace 只刪除一張貼圖，不影響相鄰一般字元。
- [ ] 刪除貼圖時穩定朗讀「刪除 [名稱]」，不亂念第一個字或鍵盤預測內容。
- [ ] 普通字元刪除仍沿用系統／使用者自己的 VoiceOver 輸入回饋設定。
- [ ] 發表後送出的內容仍是原始 Bilibili token，而不是 U+FFFC。

任何一項失敗，都視為 iOS 富文字 VoiceOver regression。

## 穩定基準

目前可作為未來更新比對點的完整實機基準：

```text
2a14e69b480dabb5d6bbf94bb17e8677a299f9c2
```

這個基準已確認：

- 真正 native `UITextView` 編輯。
- inline `NSTextAttachment` 命名。
- VoiceOver 字元轉輪逐張朗讀圖片表情。
- 一張貼圖一個 selection slot。
- 表情面板後鍵盤恢復。
- 有 attachment 時雙擊跳文字開頭／結尾。
- 跳轉後插入點位置公告。
- attachment 一次 Backspace 刪除。
- 貼圖刪除 VoiceOver 回饋穩定化。

未來若需要重構，優先保留以上**使用者可觀察行為**，而不是機械保留某段舊程式；但在沒有新的實機證據前，不要移除目前已驗證成功的 native rich-text 架構。
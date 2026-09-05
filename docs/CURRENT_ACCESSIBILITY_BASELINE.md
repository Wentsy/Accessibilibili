# Accessibilibili 目前無障礙基準

這份文件記錄目前已由 VoiceOver 實機驗證通過、可作為後續開發與上游同步回歸判定的基準點。

## 目前基準

- 日期：2026-09-06
- 分支：`main`
- 已驗證基準 commit：`1ba8aacad7b2fa3720cb00f7c30a75dc7fe72d49`
- Commit：`fix(a11y): bypass TabBarView warp for home tabs`

只要後續版本沒有明確完成新一輪 VoiceOver 實機驗證，就應把這個 commit 視為目前可回退的無障礙穩定點。

這個基準包含此前已驗證的無障礙能力，以及本輪新確認的首頁導航與影視卡片行為。

## 本輪新增且不可回退的行為

### 1. 底部導航不要產生無作用的「導覽列」焦點

`lib/pages/main/view.dart` 的底部導航可以保留實際分頁按鈕，例如首頁、動態、我的，但不能額外建立一個只會朗讀「導覽列」且沒有作用的 VoiceOver 焦點。

不要重新加入只為外層容器設定的：

```dart
label: '導覽列'
```

實機驗證結果：移除這個冗餘 label 後，觸摸瀏覽底部區域可直接遇到真正有作用的分頁按鈕。

### 2. 首頁頂部分頁在 VoiceOver 模式使用直接 semantics action

重點檔案：

```text
lib/pages/home/view.dart
```

首頁的「直播、推薦、熱門、分區、番劇、影視」在 VoiceOver／accessible navigation 啟用時，不應只依賴 Flutter `TabBar` 內部的 `InkWell` activation。

目前基準使用獨立 `SemanticsRole.tab` 節點，每個分頁都有自己的 `onTap`，並直接依指定 index 切換。

VoiceOver 分頁必須保留：

- 每個分頁都是獨立焦點。
- VoiceOver 能朗讀分頁名稱。
- 目前選中的分頁有 `selected` 狀態。
- 雙擊目標分頁時，切換目標必須由該 semantics node 的 index 明確決定。
- 點目前已選分頁仍可沿用原本回到頂部的行為。

### 3. VoiceOver 模式不可使用 `TabBarView` 的非同步 warp 作為首頁分頁切換核心

這是本輪最重要的技術結論。

實機曾出現：

- 直播與推薦之間雙擊有機率不切換。
- 番劇與影視之間有機率切換失敗。
- 從直播跨頁點影視時，有機率最後落到番劇。

只修改 `TabBar` 是否可捲動、擴大命中區域，或只補 `Semantics.onTap`，都不足以完全消除問題。

根因方向是 Flutter `TabBarView`／`PageView` 對非相鄰 tab 切換使用非同步 page warp。VoiceOver 快速或重複 activation 時，這個 warp 流程可能與 controller 狀態同步競態，造成失敗或落到相鄰頁。

目前成功基準：

- VoiceOver 模式切頁使用 `controller.index = index`，不跑 tab 切換動畫。
- VoiceOver 模式內容使用 `IndexedStack`，由 `controller.index` 直接決定可見頁。
- VoiceOver 模式不讓首頁內容走 `TabBarView`／PageView warp。
- 非無障礙模式仍可維持 PiliPlus 原本的 `TabBar + TabBarView` 行為。

後續若要重新導入 VoiceOver 模式的動畫或 `TabBarView`，必須先在 iPhone VoiceOver 實機證明以下壓力測試全部穩定，否則視為 regression。

### 4. 影視作品卡必須先念主要資訊，角標最後

重點檔案：

```text
lib/pages/pgc_index/widgets/pgc_card_v_pgc_index.dart
```

原本視覺上的 `Stack` 會讓 VoiceOver 先讀封面上的「出品／獨家」和追劇數，再讀片名，造成資訊主次顛倒。

目前基準把整張作品卡整理成單一可操作語義節點，旁白順序固定為：

```text
片名 → 集數／狀態 → 追劇數 → 出品／獨家 → 按鈕
```

例如應接近：

```text
2021最美的夜 bilibili晚会，全3集，621.4万追剧，出品，按鈕
```

不能退回：

```text
出品，621.4万追剧，2021最美的夜 bilibili晚会，全3集
```

雙擊進入作品詳情與既有長按行為必須保留。

## 首頁頂部分頁必測壓力案例

任何修改 `lib/pages/home/view.dart`、`HomeController.tabController`、`TabBar`、`TabBarView`、PageView、首頁 semantics 或首頁版面結構後，至少用 iPhone VoiceOver 實機跑：

- [ ] 推薦 → 直播，連續來回切換至少 10 次。
- [ ] 直播 → 推薦，連續來回切換至少 10 次。
- [ ] 番劇 → 影視，連續來回切換至少 10 次。
- [ ] 影視 → 番劇，連續來回切換至少 10 次。
- [ ] 直播 → 影視，跨多頁切換至少 10 次。
- [ ] 影視 → 直播，跨多頁切換至少 10 次。
- [ ] 每次雙擊後，頂部 selected 狀態與實際內容頁一致。
- [ ] 不出現「點影視卻進番劇」等相鄰頁偏移。
- [ ] 不出現 VoiceOver 已觸發按鈕但內容完全沒有切換。
- [ ] 點目前已選分頁仍能正常執行既有回頂行為。

以上任何一項失敗，都不能把新實作視為等價替代。

## 影視卡片必測

- [ ] 一張作品卡只形成一個主要 VoiceOver 焦點。
- [ ] 先朗讀片名。
- [ ] 接著朗讀集數／狀態。
- [ ] 再朗讀追劇數。
- [ ] 「出品／獨家」等角標最後才出現。
- [ ] 雙擊可正常開啟作品。
- [ ] 既有長按／次要操作沒有被語義合併破壞。

## 本輪相關 commits

以下 commit 已包含在目前基準 ancestry 中：

```text
ae3fe2b7bcc054853e00ee3cb2b0ee93f0aea007  fix(a11y): remove redundant bottom navigation label
83adeb1da54b7f0cf97d58445f1ce460d879ee8d  fix(a11y): stabilize home tab activation with screen readers
17cf590a98d15dd61aa720b6f5423c7ebf1c610e  fix(a11y): reorder cinema card semantics
8606097a1abb6d828bea2348226bfe65c5b216e7  fix(a11y): use direct semantics actions for home tabs
b0021bc735bd1808f13e9f07d352e62848af36ce  fix(a11y): add missing dart:ui SemanticsRole import for home tabs
1ba8aacad7b2fa3720cb00f7c30a75dc7fe72d49  fix(a11y): bypass TabBarView warp for home tabs
```

## 與其他基準文件的關係

這份文件是目前整體穩定點的最新指標。其他專項規格仍應同時遵守：

```text
docs/ACCESSIBILITY_MAINTENANCE.md
docs/VOICEOVER_SEMANTICS_BASELINE.md
docs/IOS_RICH_TEXT_VOICEOVER_BASELINE.md
docs/LIVE_ACCESSIBILITY_BASELINE.md
```

尤其 iOS 富文字圖片表情、評論／樓中樓、三指翻頁、焦點／viewport 同步等既有規則，不因本次首頁導航基準更新而失效。

若其他文件中的「目前基準 commit」仍指向較早版本，以本文件記錄的最新已實機驗證 commit 為準；待下次維護文件整理時再同步舊指標。

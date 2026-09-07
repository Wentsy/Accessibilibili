# Accessibilibili 目前無障礙基準

這份文件記錄目前已由 VoiceOver 實機驗證通過、可作為後續開發與上游同步回歸判定的基準點。

## 目前基準

- 日期：2026-09-08
- 分支：`main`
- 已驗證基準 commit：`a30dbbe67c37553e89c3d9e05eda97640df1819a`
- Commit：`fix(ios): promote background playback for Magic Tap`

只要後續版本沒有明確完成新一輪 VoiceOver 實機驗證，就應把這個 commit 視為目前可回退的無障礙穩定點。

這個基準包含此前已驗證的無障礙能力、首頁導航與影視卡片行為、動態投票語義，以及本輪實機確認的 iOS 影片音訊行為：開始播放不截斷 VoiceOver、背景播放、桌面／鎖屏 VoiceOver Magic Tap 播放暫停、回到 App 後 VoiceOver 正常朗讀。

## iOS 影片音訊穩定基準

播放影片時，VoiceOver 正在朗讀的內容不能被影片音訊中途切斷；背景播放設定開啟後，回主畫面與鎖屏也必須持續播放。系統將背景播放當作 Now Playing 時，桌面與鎖屏的 VoiceOver 雙指雙擊必須可以暫停與恢復，回到 App 後仍可正常閱讀。

這組行為由下列邊界共同維持：

- `lib/services/audio_session.dart`：前景使用 `playback + mixWithOthers`，讓 VoiceOver 與影片共存；`hidden/paused` 才改為主要 playback session，使系統把 Magic Tap 路由給 Accessibilibili；`resumed` 先恢復混音。
- `lib/plugin/pl_player/controller.dart`：iOS 使用 `audiounit`，並保留 `audiounit-skip-session-management=yes`，由 App 管理 shared AVAudioSession；不要讓 libmpv 再自行 activate/deactivate session。
- `packages/flutter_volume_controller`：音量觀察只讀取／觀察 output volume，不能改寫 category、activation，也不能在取消監聽時停用 shared session。
- `lib/services/audio_handler.dart`：保留 `MediaAction.playPause` 與背景 media click 對影片播放器的即時 toggle；否則音訊仍可播放，但系統的切換指令可能失效。

不要把這些檔案各自還原成上游預設實作。它們的互動關係是這項實機基準的一部分；完整排查記錄見 `docs/IOS_BACKGROUND_AUDIO.md`。

## 動態投票穩定基準

`lib/pages/dynamics/widgets/vote.dart` 的每個投票選項、圖片投票與百分比選項都必須是單一可操作的 VoiceOver 節點。朗讀內容是選項文字、已選取狀態、百分比（顯示比例時）及「雙擊選擇／取消選擇」提示；不能把圖片、勾選圖示、比例進度條、百分比 badge 與文字拆成一串重複焦點。

投票建立頁的「顯示投票比例」和「匿名投票」也必須各自朗讀為已勾選／未勾選的可切換控制。可選項數必須朗讀成「N 項，最多可選擇 M 項」，不重複加上「已選擇」或「投票選項」等無資訊前綴。

同步上游時保留外層 `Semantics`、`selected/checked`、共用 `onTap` 以及內層 `ExcludeSemantics`；這些是投票能可靠操作且不冗讀的必要組合。

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
f2ae922820e20ef8864afba60e451a4fa7c78505  fix(ios): preserve VoiceOver speech during playback
334d747e088f6b43712f46b9ac6d68750397cb2b  fix(a11y): expose poll selection state
cc667db9c824dc422bb3a34b47f1999e5d5b7a26  fix(a11y): trim redundant poll labels
6097c507ffcfda8ab4bac8b2c8cf2d19cc5224cd  fix(ios): preserve playback session during volume observation
0f23684bdf06d6eb14471b1f1700f4559ee19a79  fix(ios): resolve patched volume plugin override
6a800285dcd67619ab4cb2567ace11e51d43df3f  fix(ios): enable background VoiceOver playback toggle
a30dbbe67c37553e89c3d9e05eda97640df1819a  fix(ios): promote background playback for Magic Tap
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

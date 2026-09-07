# iOS 背景音訊：音量插件覆寫 session

## 後續實機確認與背景 Magic Tap

使用者已確認套用 `6097c50` 與依賴解析修正 `0f23684` 後，回主畫面及鎖屏
皆可持續播放。這兩筆修正是背景音訊成功基準，後續應保留。

背景雙指雙擊另有獨立問題：AudioService 的 systemActions 原本只有 seek。
鎖定 audio_service 原生實作在 activateCommandCenter 註冊 togglePlayPause，
但隨後 updateControl 根據 controls/systemActions 的 actionBits 更新 enabled；
漏報 MediaAction.playPause 就會禁用 togglePlayPauseCommand。

本次補上 playPause，讓每次狀態更新與暫停後都保有系統切換指令。
背景 media click 在一般影片播放時直接走 togglePlaybackAccessible，以播放器
實際狀態決定暫停／播放，與 App 內 Magic Tap 一致；保留聽影片頁的專用
onPlay/onPause callbacks 及其他媒體按鈕處理。不新增 debounce、計時器或
額外等待，也不改音訊 session 與已成功的背景播放設定。

實機驗證已通過：播放中回主畫面／鎖屏，雙指雙擊可暫停及恢復；回 App 後
VoiceOver 正常朗讀。
手勢辨識時間與媒體控制權由 iOS 管理，不能保證其他 App 自訂 Magic Tap、
通話或另一個媒體 App 接管時仍控制 Accessibilibili。此環境無 Flutter/Xcode，
尚未做本次編譯或手勢延遲實測。

### 第二次實機結果與 session 角色切換

`6a80028` 補齊 playPause 後，使用者確認桌面與鎖屏 Magic Tap 仍完全無效。
原生 target 與 Dart handler 已存在，失效點在更前面：持續使用
playback + mixWithOthers 會讓 iOS 將 App 視為次要混音來源，Now Playing 與
全系統 Magic Tap 不會選中它。單純增加 command action 無法改變 session 身分。

新的處理依 lifecycle 切換同一個 App-owned AVAudioSession：

- resumed / inactive：playback + mixWithOthers，維持前景 VoiceOver 共存。
- hidden / paused 且背景播放開啟：非混音 playback，使 App 成為可接收
  MPRemoteCommandCenter 與 Magic Tap 的主要播放來源。
- resumed 時先恢復 mixWithOthers；request generation 防止快速進出前背景時
  較舊的非同步 configure 最後覆寫新狀態。

不改 libmpv skip-session-management、AudioUnit、背景 video-sync 或播放器
pause/dispose 行為。2026-09-08 已完成實機回歸：背景 Magic Tap、回前景朗讀、
進出背景瞬間的 VoiceOver 語音完整性均通過；此版本 `a30dbbe` 是目前 iOS
背景音訊與 VoiceOver 的穩定基準。其他媒體 App 已在播放時的競合行為仍應在
日後變更 session 邏輯時額外驗證。

## 調查基準與已確認的程式路徑

本次以 main `3e612e8ac404ab90ace464475e0cd69f3db9d7fb` 為起點。
使用者確認 `0742107` 之後前景播放與 VoiceOver 共存成功，但回主畫面或
鎖屏會淡出停止、回前景淡入恢復。後續已在 iPhone 實測完成修正。

前面的修復必須保留：

- `7737b6791`：vendored libmpv v0.7.2，具 shared-session 補丁。
- `0742107`：`audiounit-skip-session-management=yes`，由 App 管理 session。
- 啟動時暖機、`.playback + mixWithOthers`、正常 pause/dispose 不停用 session。
- `d3669cbda` 的 activation、`66d04db84` / `a3c480ba3` 的背景 video-sync、
  `3e612e8ac` 的 interruption 處理此次不改；原有緩衝機制也不改。

## 根因

`PLVideoPlayer` initState 呼叫 FlutterVolumeController.addListener，未傳 category。
鎖定版本 2.0.2 的 Dart 預設 category 是 ambient。iOS VolumeListener.onListen
接著呼叫 VolumeController.setAudioSessionCategory，其實際動作是：

1. `AVAudioSession.setCategory(.ambient)`，覆寫啟動時的 playback 設定。
2. `setActive(true)`。

ambient 允許混音，所以 VoiceOver 仍然正常，但不提供鎖屏背景播放行為。
這是可由程式碼確認的 session 所有權衝突；後續已由實機背景播放驗證。Dart
端 configure 的快取不會反映其他插件改寫的原生 category，
僅 setActive(true) 不會恢復 playback category。

此外，VolumeListener.onCancel 會 setActive(false)，播放器 UI 釋放或重新
監聽時可能停用同一個 session；插件 applicationWillEnterForeground 又會
activate。這些隱藏的所有權變更一併移除。

## Native 排查

- 實際 Makefile 下載 media-kit/libmpv-darwin-build v0.7.2，SHA-256 不變。
  該 tag 的 packages.lock.nix 指向 mpv v0.36.0；
  patches/mpv-audiounit-shared-session.patch 受 skip-session-management 保護。
- ao_audiounit.m 的 AudioOutputUnitStop 只在 reset/stop 與 uninit 路徑，
  沒有 UIApplication/UIScene background observer；此次不改二進位。
- media_kit_video Darwin 原生輸出中未找到背景音訊 stop/suspend 分支。
- audio_service 的 iOS 原生插件提供遠端播放控制，未找到 app/scene 背景
  setActive(false) 或 AudioUnitStop 分支。
- Runner 已有 UIBackgroundModes=audio；沒有需要另補的 scene 音訊停止邏輯。

## 修正

將已鎖定的 flutter_volume_controller 2.0.2 納入 packages，iOS 音量讀取與
監聽只觀察音量，取消監聽只移除 observation，不接管 category/activation。
不以「註冊後再 configure」補救，避免非同步競態與中途重建路由。
也不能單純把 addListener category 改為 playback：原生 category-only setter
沒有 mixWithOthers，可能重新截斷 VoiceOver。

來源：

- https://github.com/yosemiteyss/flutter_volume_controller/tree/def69b5f049aa9018b9c875200a1ffae7e99fe62
- https://github.com/media-kit/libmpv-darwin-build/tree/v0.7.2
- https://github.com/mpv-player/mpv/blob/v0.36.0/audio/out/ao_audiounit.m
- https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/ambient

## 驗證

開發環境沒有 Flutter SDK、Xcode 或 iPhone；初次修正時以來源差異與依賴路徑
檢查為準，後續由使用者 iPhone 實機驗證通過。

Hermes 拉取 main 後執行 flutter pub get、cd ios && pod install，再正常編譯
與簽名。此版更換了原生插件來源，必須重編 IPA，hot reload 不會生效。

實機確認：

1. 背景播放開啟：播放中回主畫面與鎖屏，各等待至少 30 秒，音訊與進度持續。
2. 回前景不中斷；VoiceOver 正在朗讀時開播、暫停、離開影片不吞字。
3. 重複進出影片後再鎖屏，排除音量監聽取消／重建造成的 session 停用。
4. 實體音量鍵與 App 音量控制正常，音量指示仍會更新。
5. 背景播放關閉時仍按原設定暫停；耳機拔出與鎖屏暫停／播放控制正常。

若仍失敗，需在實機記錄原生 category/options、interruption userInfo 及 mpv
pause/core-idle/audio-pts，而不是回退已成功的 VoiceOver session 所有權修復。

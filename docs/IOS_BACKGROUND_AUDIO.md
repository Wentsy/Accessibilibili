# iOS 背景音訊：音量插件覆寫 session

## 調查基準與已確認的程式路徑

本次以 main `3e612e8ac404ab90ace464475e0cd69f3db9d7fb` 為起點。
使用者確認 `0742107` 之後前景播放與 VoiceOver 共存成功，但回主畫面或
鎖屏會淡出停止、回前景淡入恢復。此次修正尚待 iPhone 實測。

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
這是可由程式碼確認的 session 所有權衝突；與使用者現象吻合，最終效果仍需
裝機驗證。Dart 端 configure 的快取不會反映其他插件改寫的原生 category，
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

開發環境沒有 Flutter SDK、Xcode 或 iPhone，不能在此宣稱編譯或實機通過。
已做來源差異與依賴路徑檢查；非 iOS 平台程式維持上游內容。

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

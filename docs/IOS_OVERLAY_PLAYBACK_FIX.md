# 控制中心／通知中心播放交接與進度同步（待實機驗證）

2026-09-10。以 main 59128cae6 為起點；已驗證穩定基準仍是
CURRENT_ACCESSIBILITY_BASELINE.md 記錄的 533d86b，本次修改尚未列為穩定基準。

## 原因與修改

- 原生音訊原先只在 didEnterBackground 取得非混音的系統播放角色。
  控制中心、通知中心只讓 scene inactive，因此 App Magic Tap 收不到，
  系統也沒有完成交接。
- 原生新增 UIScene.willDeactivateNotification（舊 iOS 使用
  UIApplication.willResignActiveNotification），提前沿用原本的交接方式。
  Flutter inactive 同步採用系統角色作為非同步備援。
- 恢復混音改在 didActivate／didBecomeActive，避免從背景進入 inactive
  時太早收回控制權。起播仍維持 mixWithOthers 與 mpv skip-session-management。
- 保留背景播放設定開關、真正退背景的備援，以及已暫停時約兩秒的
  零音量 bridge。未延長為持續靜音播放。
- 播放頁共用 ProgressBar 的 progress／total setter 原本只刷新繪製，
  未標記 semantics 更新，造成 VoiceOver 快取舊時間。現在同步更新
  semantics；拖曳與 onSeek 可用性改變也同步。沒有新增主動朗讀通知。

## 驗證

新增 test/player_progress_semantics_test.dart：同一語義節點隨播放更新時間、
百分比與上下滑目標；快轉仍傳毫秒；總時長和可調整狀態更新。
本次開發環境沒有 Flutter/Dart SDK 或 Xcode，尚未執行 widget test 或 IPA 編譯。
可在 Hermes 編譯環境執行：

```sh
flutter test test/player_progress_semantics_test.dart
```

實機待測：

- 播放頁直接拉下控制中心、通知中心，雙指雙擊可暫停及繼續。
- 控制中心媒體按鈕可暫停及繼續。
- 先在播放頁暫停，再拉下上述介面，仍可繼續。
- 收回上述介面後，App 內旁白及雙指雙擊正常；快速反覆開關不失效。
- 保留桌面／鎖屏播放與 paused-first 等待 10 秒／1 分鐘恢復。
- 影片起播不截斷旁白；系統介面轉場也檢查旁白與影片聽感。
- 播放 20 秒後重摸進度列，時間應前進；上下滑仍以 10 秒調整。
- 全螢幕、非全螢幕、控制列顯示／隱藏均檢查。
- 暫停時間不跑；恢復後繼續更新，不每秒主動插話。

inactive 也包括來電、系統提示等暫時失焦，本次沿用既有背景音訊策略；
仍需確認這些轉場可正常恢復，不把一次成功測試當作全部情境已驗證。

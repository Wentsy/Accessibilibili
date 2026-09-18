Telegram 7.2.9 直接整合無障礙修改

這個目錄不是 NVDA 外掛，也不是外部輔助程式。
GitHub Actions 會抓官方 Telegram Desktop 7.2.9 原始碼，套用 apply_patch.py，
再直接編譯出修改過的 Telegram.exe。

第一個測試版本只做最核心、風險最低的焦點修正：
- 螢幕閱讀器模式下，FieldAutocomplete 不再攔截 Tab。
- 編輯區 Tab 一次直接將焦點移至聊天訊息清單。
- 同時覆蓋 HistoryWidget 與新版 ChatWidget 路徑。
- 不更動 Telegram 原生語音訊息 Space 播放邏輯。
- 編譯時停用自動更新，避免測試版被官方版本覆蓋。

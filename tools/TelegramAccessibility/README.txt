TelegramAccessibility

目的
- 不依賴 NVDA 附加元件。
- 只在 Telegram.exe 位於前景時工作。
- 不持續掃描 Telegram 訊息樹，避免大量訊息聊天造成卡頓。

目前行為
1. 訊息輸入框按 Tab：
   - 正常先送一次 Tab。
   - 如果焦點落到 Telegram 的 Bot Commands / /help 命令區，立即再送一次 Tab，跳到訊息清單。
2. 語音/音訊訊息：
   - 訊息清單上的 Space 完全交給 Telegram 原生處理，不攔截。
3. Bot 命令與一般按鈕：
   - Enter / Space 優先使用 UI Automation 的 Invoke / Toggle / Selection / DefaultAction。
   - 若控制項沒有標準動作，最後才用目前控制項中心點模擬滑鼠點擊。
4. 方向鍵：
   - 不攔截，交給 Telegram 原生處理。
5. 系統匣：
   - 可暫停「啟用鍵盤增強」或直接結束程式。

這是第一個測試版，優先驗證：
- Hermes 機器人聊天：輸入框一次 Tab 是否直接到訊息清單。
- /help 命令區是否不再卡在中間。
- 命令項目 Enter/Space 是否能執行。
- 語音訊息 Space 是否仍正常播放/暫停。

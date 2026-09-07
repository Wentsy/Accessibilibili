# 進入／退出播放的音訊交接（待 iPhone 驗證）

基於使用者指定的 `main: bc8e1fa`。保留已驗證有效的自動緩衝參數、
倍速緩衝更新與此前減少載入旁白的修改。

## 參考與判斷

檢查 `Wentsy/uYouPlus/Sources/uYouPlusPatches.xm` 的 PlayerVC.close
與 HAMPlayerInternal.play：關閉清除舊來源，播放時暫停另一個播放器。
可借鑑的是避免舊播放器與新播放互相干擾；這不是 VoiceOver 淡入淡出
實作，YouTube 核心播放器與 uYou 本身並未在該倉庫開源。

Accessibilibili 原本在 media-kit 已開始播放後，才不等待地呼叫
audio_session.setActive(true)；configure 也沒有等待完成。pause 與
setActive(false) 沒有序列化，最終 dispose 沒有配對 session 釋放。
因此先修正交接順序，不加固定延遲、音量漸變或語音完成計時器。

## 修改

- 等待 session.configure 完成後才操作啟用／停用。
- 先成功取得音訊 session，再開始播放；被拒絕時保持暫停。
- play、pause、最終 dispose 共用序列佇列；舊播放器清理完成後，
  新播放器才能取得 session，避免舊清理晚到而停用新影片的 session。
- 每次播放／暫停／最終釋放都有請求世代檢查。若啟用尚未完成便退出，
  舊請求不能在退出後開始播放。
- 確認 media-kit 暫停後才停用 session；最終釋放也先暫停並等待
  dispose，再停用。iOS 停用使用 notifyOthersOnDeactivation。
- pop 即使暫時還沒顯示 playing，也會取消等待中的播放請求。
- 佇列中的平台操作失敗會回報該次呼叫，但不阻塞之後的暫停與清理。
- 不修改系統音量、VoiceOver 音量閃避或背景播放設定。

注意：iOS 一般 VoiceOver ducking 由系統處理；audio_session 的 iOS
interruption 轉換主要是 pause／unknown。沒有把既有 Android duck
回呼當成已確認的 iOS 問題來源，也沒有在此輪更動該回呼。

## 驗證

已用獨立 Dart 執行環境，抽取實際 play、pause 與最終音訊清理程式，
配合假的 session／player 執行六項檢查：

1. 啟用完成後才播放，暫停完成後才釋放。
2. 等待啟用時按暫停，不會稍後意外出聲。
3. session 拒絕啟用時不播放。
4. 舊播放器清理不能晚於新播放器啟用。
5. 啟用期間 dispose 會取消播放並清理。
6. 一次平台錯誤不會使佇列永久失效。

六項通過，隔離程式 Dart analyze 無問題；修改檔語法解析與
git diff --check 通過。這不是完整 Flutter 分析、iOS 編譯或實機
聽感驗證。此前 Flutter 工具啟動因 metadata 存取被自動審查拒絕，
本輪使用獨立 Dart，不重試該被拒絕的啟動路徑。

Hermes 編譯後請用 iPhone 測試：正常起播／返回、快速進入立即返回、
返回後立即開另一部影片、Magic Tap 快速暫停／恢復、來電中斷／恢復、
耳機拔除、背景播放與畫中畫、換集／換畫質。留意影片開頭不被吞掉、
退出後不殘留聲音、旁白恢復及音量正常。未實測前不更新穩定基準。

參考：
- https://github.com/Wentsy/uYouPlus/blob/main/Sources/uYouPlusPatches.xm
- https://pub.dev/documentation/audio_session/0.2.4/audio_session/AudioSession/setActive.html

# 國際版確認後無法登入：掃碼相容實驗

基於 `experiment/web-cookie-tv-authorization`，保留既有掃碼為預設。
這不是已確認的國際版修復；需要手機上的已登入帳號完成確認才能驗證。

## 已確認的實作差異

- Cookie 匯入不會產生 App access token；點讚用 App HTTP API，私信用 gRPC。
- 原有掃碼申請帶 `platform=android`、`mobi_app=android_hd`，伺服器回傳的
  二維碼 URL 帶 `mobi_app=android_hd`。
- 新增可選的「相容掃碼（實驗）」：不帶上述可選平台參數，使用表單 POST。
  App key、簽章與既有 HD 憑證用途保持一致；沒有改用另一種 App key。
- 兩種模式皆已從此環境實際申請成功（code 0），並在尚未掃碼時輪詢得到
  86039。相容模式的回傳 URL 不帶 mobi_app。這只能證明申請／等待可用，
  不能證明國際版確認後能取得 App token，更不能證明帳號所有功能皆可用。
- 參考協議：https://github.com/replace5/bilibili-API-collect-mirror/blob/main/docs/login/login_action/QR.md

## 修改內容

- 在原有掃碼頁增加相容模式切換；切換會重新申請二維碼。
- 輪詢兼容平鋪 token 與 token_info；保存前要求 App token 與必要 Cookie，
  並檢查 token MID（若存在）與 Cookie MID 一致。缺少憑證不會顯示登入成功。
- 等待狀態繼續輪詢，明確失敗停止輪詢並顯示錯誤碼；網路異常可在有效期內重試。
- 刷新／離開後忽略舊請求回應，避免舊碼覆蓋新碼或延遲登入。
- 提供複製診斷：模式、階段、錯誤碼、經過遮蔽的訊息、憑證存在與否。
  不包含 Cookie／token 值、UID、二維碼 URL 或 auth_code。

## 手機驗證

1. 保留國際版的現有登入。在 Accessi 登入頁選「掃碼」。
2. 先關閉相容模式，用國際版掃碼並確認；若失敗，複製掃碼診斷。
3. 開啟「相容掃碼（實驗）」，掃描新碼並確認；若失敗，同樣複製診斷。
4. 若成功，確認 Accessi 主帳號為預期的小號，再驗證點讚與私信。
   帳號等級、平台風控等限制仍由 B 站決定。
5. 用大陸版帳號測試預設模式，確認原有登入沒有回歸。

不要回傳二維碼網址、Cookie、完整 API 回應或登入憑證。

## 自動檢查

`flutter test test/models/qr_login_test.dart`

涵蓋兩種 token 結構、Cookie-only 回應、缺少 CSRF、MID 不一致、等待／失效／拒絕、
異常回應，以及可複製診斷不洩漏測試憑證。

本次驗證結果：

- 五項解析／診斷測試在同版 Flutter 的隔離測試專案通過（複製未改動的生產模型與測試）。
- 本次修改的 Dart 檔案與測試靜態分析：No issues found。
- 原專案直接執行測試被既有 cnativeapi Linux native-assets hook 阻擋：環境缺 GTK/X11/Xi
  開發套件，且沒有安裝系統套件的權限；不能將隔離測試通過視為整個 App 測試通過。
- iOS 建置另由原有 GitHub Actions 工作流程驗證；真實帳號授權需手機實測。

# 國際版帳號 UP 關注狀態修正

基於 main 4fa1e145dbf697ddad693f0262f456920bfb0c62。待使用者實測，不取代現有穩定基準。

## 修改

國際 Passport 帳號進入 UP 頁時，並行取得 App 空間資料與 Cookie /x/relation 關係資料，兩者完成後才發布頁面狀態。關係查詢綁定該 controller 的帳號，與關注／取消關注使用相同主帳號來源。成功時以關係資料覆蓋 App 空間的關注值；保留特別關注、黑名單，將 Web 互關 attribute 6 映射至此 controller 的 4。查詢失敗保留原有空間資料並顯示錯誤，不假造成功結果。中國版登入維持原路徑。

## 本次程式碼檢查範圍

檢查 MemberController、MemberHttp、UserHttp.userRelation、VideoHttp.relationMod、RequestUtils.actionRelationMod、AccountManager、ApiType 與關係顯示元件。

- 關注修改、取消及分組管理使用 Cookie／CSRF；空間頁使用 App access_key，兩者關係狀態來源不一致是本次修正目標。伺服器實際回應尚未擷取，根因為程式碼與使用者症狀對照判斷。
- 國際 Passport 自動刷新及請求帳號綁定已存在；不應把全部 REST API 強制改成國際 App 簽名，現有程式明確保留各端點身分。
- 推薦、播放、歷史可使用獨立帳號設定，與主帳號呈現差異不必然是國際版故障，本次不改動這些設定。
- 空間頁被關注狀態、充電／勳章及其他個人化欄位仍由 App 空間回應提供；可能存在同類相容差異，但本次沒有實機證據，未宣稱有故障或已修復。

未編譯、未執行回歸或防禦型測試，交由 Open Code 編譯並由使用者驗證。此檢查不代表所有國際版與中國版功能已全面比對。

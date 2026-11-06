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


## 2026-11-07：延伸檢查與同批修正

本輪檢查影片關注／讚／投幣／收藏、番劇追番、課程收藏、動態讀取、直播頁、評論互動，以及帳號分流與 gRPC headers；未執行回歸或防禦型測試，也未進行帳號實機操作。

新增修正：

- 課程收藏狀態原先直接使用 pgcItem.userStatus.favored；Api.pugvInfo 預設被分流到歷史帳號，而收藏增刪屬主帳號。SearchHttp.pugvInfo 新增可選帳號參數，課程頁額外使用主帳號取得收藏狀態。收藏／取消前再同步伺服器狀態，成功後指定目標狀態，不對可能已變動的本地值盲目 toggle。只更新收藏標記，不覆蓋原先歷史帳號的進度或播放資料。
- ReplyItemGrpc 尚未走 ReplyA11ySemantics 的入口，旁白讚／踩固定 type=1、action=1，成功後未更新 replyControl.action／like，導致非影片評論送錯類型，也無法取消。改用實際評論 type，依目前狀態送出增加／取消，成功後同步狀態、讚數與旁白動作名稱；讚改踩時同步扣除原讚。

確認現況：

- 一般影片另以 videoRelation、userRelation／relations 查詢主帳號互動狀態；番劇另用 seasonStatus、pgcLikeCoinFav。沒有套用 UP 空間 App 關係值的同一缺口。
- 動態主要列表使用 Web API；gRPC headers 已按 internationalPassport 選擇 iphone_i，不能把歷史說明中的 Android HD 固定身分當成目前所有 gRPC 的現況。
- 直播房間資訊仍可按使用者設定分流至歷史帳號；未發現此頁有與本次 UP 關注按鈕相同的操作入口，沒有改動整頁帳號來源。
- 課程與評論修正對兩種登入都適用；它們是程式碼可確認的狀態來源／同步問題，並非宣稱使用者已遇到或實測通過。

以上與先前 UP 關注修正放在同一分支，由 Open Code 一次編譯。穩定基準暫不更新，待使用者確認。

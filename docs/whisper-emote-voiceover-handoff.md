# 私信表情 VoiceOver 修正

本次接續 fix/international-member-follow-state，包含該分支既有 UP 關注、課程收藏及評論互動修正。

- 私信在 iOS 改用評論現有 IOSNativeRichTextField，將 RichTextItem.rawText 的表情名稱交給原生附件標籤；表情選擇面板、readOnly 切換與發送 editController.rawText 的流程不變。原生編輯器保持 1 至 4 行，點擊唯讀區會切回鍵盤。
- 私信文字訊息使用原始 content.content（含命名表情 token）作為整段旁白內容，圖片 WidgetSpan 不再額外暴露為無名附件。文字、標點、表情依原訊息順序朗讀；未知表情名稱也保留原字串。
- 保留畫面上的表情圖片、點擊預覽、文字選取與連結手勢。合併訊息朗讀後，URL 另透過既有 TextLinkRotor 提供，啟用時沿用原私信 PiliScheme.routePushFromUrl。
- 只處理文字訊息及編輯器，不將照片、影片等訊息型態誤當表情。

依使用者要求未編譯、未執行回歸／防禦型測試。由 Open Code 取本分支最新提交編譯，待使用者確認後再更新穩定基準。

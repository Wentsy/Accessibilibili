# 動態評論與圖文提示修正（已實機確認）

- 基於 main `4664ba15c3a45735ffd32e2ef3fc45b76f20341e`。
- 既有連續朗讀穩定基準仍以 `comment-read-all-current-baseline.md` 為準；本次功能提交 `7039c1e8e864891cfa29ac2577e498017c3a3f7b` 已由使用者回報測試通過，納入穩定基準。

## 本次修改

- 評論有圖片資料時，顯示文字與 VoiceOver 標籤移除固定的「[请升级到App最新版本查看图文评论]」提示（亦涵蓋繁體寫法），保留其他文字和圖片標示。不修改原始評論資料、圖片擷取及帳號登入設定。
- iOS VoiceOver 的動態詳細頁評論改用影片評論的 `ReplyReadingSliver`、`ReplyA11ySemantics`、`ReplyPaginationStatus` 與 `ReplyPagedScroll`。
- 首批與焦點前方評論不足時，沿用現有 controller 的 30／60 則預載、共用載入及失敗重試。新增評論保留既有閱讀批次，不把載入中文字放進正常閱讀順序。
- 直向使用 NestedScrollView 的內層 controller，讓語意捲動範圍對應真正的評論 viewport；橫向使用評論 controller。保留動態正文、分頁、底部操作以及三指翻頁。
- 動態評論保留雙擊展開回覆／更多操作；轉輪的更多操作、讚／踩和評論文字連結仍可使用。
- 其他平台及其他文章入口維持原有列表；影片評論沿用既有預設 controller。

## 交接

依使用者要求，未編譯 IPA，未執行回歸或防禦型測試；僅檢閱修改內容與差異格式。由 Open Code 接手編譯與版本號遞增，使用者已回報國際版帳號圖文評論及動態評論左右滑動修復測試沒有問題。

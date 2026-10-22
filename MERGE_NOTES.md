# 上游同步進度（PiliPlus 2.1.6.2 + 到 2026-10-22 的 commit）

分支：main（本地 C:\Users\wents\Documents\Accessibilibili）
上游：upstream = bggRGjQaUbCoE/PiliPlus，已 fetch 到 006c0fdd1
自家：origin/main = cfcf25943（2.1.3+5737 基準 3767e1c67）
merge-base：35e5454a47246c187106b869cd02b9bdbe90c015
狀態：merge 進行中，尚未 commit

## 已完成（純 import 衝突，兩邊 union）
lib/common/widgets/flutter/list_tile.dart
lib/models_new/download/bili_download_entry_info.dart
lib/pages/follow_type/view.dart
lib/pages/later/widgets/video_card_h_later.dart
lib/pages/live/view.dart
lib/pages/match_info/view.dart
lib/pages/msg_feed_top/at_me/view.dart
lib/pages/msg_feed_top/like_me/view.dart
lib/pages/msg_feed_top/reply_me/view.dart
lib/pages/msg_feed_top/sys_msg/view.dart
lib/pages/rcmd/view.dart
lib/pages/whisper/view.dart

## 待處理 41 個（依難度分三級）

### A. 小改、可機械處理
- .gitattributes（兩邊相加）
- ios/Runner/AppDelegate.swift（theirs 的 PipPlugin 區塊放前面，再放 ours 全部）
- lib/utils/date_utils.dart（兩邊相加）
- lib/pages/setting/models/video_settings.dart（文字說明，取 theirs 較新）
- lib/utils/storage_pref.dart
- pubspec.yaml / pubspec.lock
- lib/common/widgets/image/network_img_layer.dart（ours 包 Semantics，theirs 加 gaplessPlayback → 要合併成 Semantics 內含新參數）

### B. 自家 a11y wrapper vs 上游小重構（需人工接）
- lib/pages/main/view.dart（底部留白）
- lib/pages/history/widgets/item.dart
- lib/pages/pgc/widgets/pgc_card_v.dart
- lib/pages/pgc_index/widgets/pgc_card_v_pgc_index.dart
- lib/pages/fav_panel/view.dart
- lib/pages/fav/note/widget/item.dart
- lib/pages/fav/pgc/widget/item.dart
- lib/pages/fav_detail/widget/fav_video_card.dart
- lib/pages/member_cheese/widgets/item.dart
- lib/pages/member_video/view.dart
- lib/pages/subscription/widgets/item.dart
- lib/pages/main_reply/view.dart
- lib/pages/dynamics_tab/view.dart
- lib/pages/dynamics_detail/view.dart
- lib/pages/article/view.dart
- lib/pages/common/dyn/common_dyn_page.dart

### C. 核心（四情境相關，絕不能丟）
- lib/pages/video/reply/view.dart（FAB + ReplyPaginationStatus + replyReply）
- lib/pages/video/reply_reply/view.dart
- lib/pages/video/introduction/ugc/view.dart（展開/摺疊簡介）
- lib/pages/video/introduction/ugc/controller.dart（分享 dialog，上游自建 SimpleDialog）
- lib/pages/common/reply_controller.dart（onA11yReplyLoadMore 等）
- lib/pages/video/controller.dart（_initPlayerIfNeeded 改名 + HDR 查詢）
- lib/pages/video/reply/widgets/reply_item_grpc.dart
- lib/pages/video/reply/widgets/zan_grpc.dart（_announce）
- lib/pages/video/reply_new/view.dart
- lib/pages/live_room/widgets/chat_panel.dart（上游改 LiveListView）
- lib/pages/live_emote/view.dart
- lib/pages/live_room/send_danmaku/view.dart
- lib/pages/video/send_danmaku/view.dart
- lib/pages/video/widgets/header_control.dart
- lib/plugin/pl_player/controller.dart（8 塊）
- lib/services/download/download_service.dart（4 塊）
- lib/services/audio_handler.dart
- lib/http/download.dart（上游刪掉的區塊，要確認是不是功能搬到別處）

## 原則
- 上游已重寫的畫面：以上游結構為底，把自家的 a11y 層重新套上去，不要硬留舊 widget。
- 四情境（外層評論／展開簡介／摺疊簡介／樓中樓）功能契約不能退步。
- 舊穩定版 2.1.3+5737 不動；新版測不過就退回。

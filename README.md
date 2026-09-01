# Accessibilibili — PiliPlus 無障礙版

這是以 [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus) 為基礎的無障礙 fork，主要針對 iOS VoiceOver 使用情境進行實際改造與測試。目標不是重做 Bilibili，而是讓原本已有的功能更容易被 VoiceOver 使用者操作、瀏覽和理解。

## Accessibilibili 已整合的完整功能與無障礙改造

Accessibilibili 保留 PiliPlus 原本的 Bilibili 功能，並將本 fork 的所有無障礙改動整合在下面這份總覽中；這些項目不代表先後順序，而是目前相較原版所加入或修正的完整範圍。主要針對 iOS VoiceOver 的語義、焦點、捲動和操作方式進行改造。

### VoiceOver 語義與導覽

- 首頁、搜尋結果、UP 主頁、歷史紀錄等影片列表的卡片，整理成清楚的單一語義節點。VoiceOver 可讀取標題、UP 主、時長、播放／彈幕等資訊。
- 為影片卡加入 VoiceOver 操作：點讚、分享、更多。
- 評論整則整理成容易理解的語義節點，包含作者、內容、讚數、回覆數和圖片提示。
- 歷史紀錄影片卡、互動結果按鈕和狀態訊息補上語義、按鈕角色與 live region；點讚、投幣、收藏等結果會向 VoiceOver 正確宣告。
- 評論區的「發表評論」與相關 FAB 設置語義邊界，避免 VoiceOver 焦點從按鈕穿透到背後的評論列表。
- 在評論更多操作中加入可直接前往評論者的操作，主樓與樓中樓都能使用。
- 評論、影片卡、操作按鈕與 FAB 設置正確的語義邊界，避免焦點穿透到不該讀取的列表內容，也避免同一顆按鈕被讀成兩次。
- 移除或改寫會被 VoiceOver 誤讀成「顯示選單」但實際無法正常使用的長按操作，改成明確的自訂語義操作。

### VoiceOver 捲動、翻頁與焦點穩定性

- 為全域垂直列表、追蹤列表、評論區和樓中樓加入 VoiceOver 三指上下翻頁支援。
- 支援巢狀捲動與不同的 scroll configuration，確保 VoiceOver 操作真的連到正確的 scroll controller。
- 翻頁完成後接上 iOS 原生 `UIAccessibility.Notification.pageScrolled` 回饋，並以 120ms 去重，避免同一次手勢重複觸發；由 VoiceOver 提供原生翻頁回饋，而不是自製音效。
- 讓目前被 VoiceOver 聚焦的項目自動保持在可見範圍，降低焦點跑出畫面或滑到某個項目後只能聽到音效、無法繼續移動的「鬼打牆」問題。
- 改善分頁載入時的焦點保留、列表身份、預載、頁面去重和可視範圍計算，避免載入更多後焦點跳回第一項或列表重新排列。
- 移除會吞掉捲動操作或造成重複載入按鈕的語義容器，讓載入更多和排序等操作能被正常找到。

### 評論區與樓中樓

- 主樓評論與樓中樓都支援 VoiceOver 翻頁、穩定瀏覽和載入更多。
- 可讀取評論內容、作者、讚數、回覆數、圖片提示和使用者身份資訊。
- 提供評論的點讚、點踩、更多操作，以及樓中樓展開和回覆。
- 樓中樓真正到達「沒有更多了」後，底部會出現「發表回覆」，可對整個樓層發表回覆，不會自動錯誤地變成回覆某位樓中樓使用者。
- VoiceOver 開啟時隱藏重複的浮動「發表回覆」按鈕，避免旁白遇到兩顆相同按鈕。
- 關閉樓中樓後，原本的「發表評論」按鈕會在 bottom sheet 完整關閉後正確恢復。
- 修正巢狀評論沒有實際 controller、導致載入與翻頁動作靜默失效的問題。

### 播放器與 VoiceOver 操作

- 接通影片進度條的 VoiceOver 調整操作，支援以 ±5% 方式調整播放位置。
- 播放／暫停狀態與 VoiceOver 保持同步，播放設定變更會向 VoiceOver 正確宣告；緩衝、播放速度、畫質等狀態也維持可理解的回饋。
- 保留可持續使用的 VoiceOver 播放控制，並支援 iOS VoiceOver Magic Tap 播放／暫停。
- 緩衝期間仍維持播放控制可操作，避免控制項暫時消失或失去焦點。

### 主導航與其他修正

- 底部導覽列以目前選取索引作為唯一內容來源，首頁、動態、我的之間切換時，選中狀態和主畫面保持一致。
- 修正推薦列表、UP 主影片列表、相關影片和樓中樓分頁時的項目身份與 VoiceOver 焦點穩定性。
- iOS IPA 透過 GitHub Actions 編譯，使用者自行處理簽名與側載；本專案不提供 TestFlight。

## 改造範圍說明

上面列出的項目是 Accessibilibili fork 實際整合的改動總覽，不是另一套取代 PiliPlus 的功能清單；PiliPlus 原本的影音、搜尋、動態、帳號、收藏、私信、直播、設定等功能仍以原 README 的清單為準。

## 使用與編譯

- 本專案仍保留 PiliPlus 原有的功能與平台支援，這個 fork 的主要差異是無障礙語義、VoiceOver 導覽和 iOS 操作回饋。
- iOS IPA 透過 GitHub Actions 編譯。使用者需要自行處理簽名與側載；本專案不提供 TestFlight。
- 目前的無障礙行為主要以 iOS VoiceOver 實機測試，其他平台的無障礙表現可能不同。

## 專案來源與聲明

Accessibilibili 是非官方的個人無障礙改造 fork，感謝 PiliPlus 原作者及所有上游開源貢獻者。本專案不隸屬於 Bilibili 或 PiliPlus 官方。請遵守所在地法律、PiliPlus 授權條款及相關服務的使用規範。

---

<div align="center">
    <img width="200" height="200" src="assets/images/logo/logo.png">
</div>



<div align="center">
    <h1>PiliPlus</h1>
<div align="center">
    
![GitHub repo size](https://img.shields.io/github/repo-size/bggRGjQaUbCoE/PiliPlus) 
![GitHub Repo stars](https://img.shields.io/github/stars/bggRGjQaUbCoE/PiliPlus) 
![GitHub all releases](https://img.shields.io/github/downloads/bggRGjQaUbCoE/PiliPlus/total) 
</div>
    <p>使用Flutter开发的BiliBili第三方客户端</p>
    
<img src="assets/screenshots/510shots_so.png" width="32%" alt="home" />
<img src="assets/screenshots/174shots_so.png" width="32%" alt="home" />
<img src="assets/screenshots/850shots_so.png" width="32%" alt="home" />
<br/>
<img src="assets/screenshots/main_screen.png" width="96%" alt="home" />
<br/>
</div>


<br/>

## 适配平台

- [x] Android
- [x] iOS
- [x] Pad
- [x] Windows
- [x] Linux

[![Packaging status](https://repology.org/badge/vertical-allrepos/piliplus.svg)](https://repology.org/project/piliplus/versions)

## refactor

- [ ] gRPC [wip]
- [x] 用户界面
- [x] 其他

## feat

- [x] 编辑动态
- [x] DLNA 投屏
- [x] 离线缓存/播放
- [x] 移动端支持点击弹幕悬停，点赞、复制、举报 by [@My-Responsitories](https://github.com/My-Responsitories)
- [x] 播放音频
- [x] 跳过番剧片头/片尾
- [x] 安卓端 `loudnorm` 适配 by [@My-Responsitories](https://github.com/My-Responsitories)
- [x] Win/Mac 支持极验、短信登录 by [@My-Responsitories](https://github.com/My-Responsitories)
- [x] 视频截取动图 by [@My-Responsitories](https://github.com/My-Responsitories)
- [x] AI 原声翻译
- [x] SuperChat
- [x] 播放课堂视频
- [x] 发起投票
- [x] 发布动态/评论支持`富文本编辑`/`表情显示`/`@用户`
- [x] 修改消息设置
- [x] 修改聊天设置
- [x] 展示折叠消息
- [x] 查看用户图文
- [x] 动态话题
- [x] 直播分区
- [x] 分享`视频`/`番剧`/`动态`/`专栏`/`直播`至消息
- [x] 创建/修改/删除关注分组
- [x] 移除粉丝
- [x] 直播弹幕发送表情
- [x] 收藏夹排序
- [x] 稍后再看 ~~`未看`~~ / `未看完` / ~~`已看完`~~ 分类
- [x] WebDAV 备份/恢复设置
- [x] 保存评论/动态
- [x] 高级弹幕 by [@My-Responsitories](https://github.com/My-Responsitories)
- [x] 取消/置顶评论
- [x] 记笔记
- [x] 多账号支持 by [@My-Responsitories](https://github.com/My-Responsitories)
- [x] 屏蔽带货动态/评论
- [x] 互动视频
- [x] 发评/动态反诈
- [x] 高能进度条
- [x] 滑动跳转预览视频缩略图
- [x] Live Photo
- [x] 复制/移动/排序收藏夹/稍后再看视频
- [x] 超分辨率
- [x] 合并弹幕
- [x] 会员彩色弹幕
- [x] 播放全部/继续播放/倒序播放
- [x] Cookie登录
- [x] 显示视频分段信息
- [x] 调节字幕大小
- [x] 调节全屏弹幕大小
- [x] 收藏夹/稍后再看多选删除
- [x] 搜索用户动态
- [x] 直播弹幕
- [x] 修改头像/用户名/签名/性别/生日
- [x] 创建/编辑/删除收藏夹
- [x] 评论楼中楼查看对话
- [x] 评论楼中楼定位点击查看的评论
- [x] 评论楼中楼按热度/时间排序
- [x] 评论点踩
- [x] 私信发图
- [x] 投币动画
- [x] 取消/追番，更新追番状态
- [x] 取消/订阅合集
- [x] SponsorBlock
- [x] 显示视频完整合集
- [x] 三连动画
- [x] 番剧三连
- [x] 带图评论
- [x] 视频TAG
- [x] 筛选搜索
- [x] 转发动态
- [x] 合集图片
- [x] 删除/置顶/撤回私信
- [x] 举报用户/评论/视频/动态
- [x] 删除/发布/置顶文本/图片动态
- [x] 其他

## opt

- [x] 专栏界面
- [x] 私信界面
- [x] 收藏面板
- [x] PIP
- [x] 视频封面
- [x] 回复界面
- [x] 系统通知
- [x] 评论显示
- [x] 亮度调节
- [x] 视频播放
- [x] 视频staff
- [x] 防止bottomsheet遮挡全屏视频
- [x] 其他

## fix

- [x] 番剧分集点赞/投币/收藏
- [x] bugs

<br/>

## 功能

- [x] 推荐视频列表(app端)
- [x] 最热视频列表
- [x] 热门直播
- [x] 番剧列表
- [x] 屏蔽黑名单内用户视频
- [x] 无痕模式（播放视为未登录）
- [x] 游客模式（推荐视为未登录）

- [x] 用户相关
  - [x] 粉丝、关注用户、拉黑用户查看
  - [x] 用户主页查看
  - [x] 关注/取关用户
  - [x] 离线缓存
  - [x] 稍后再看
  - [x] 观看记录
  - [x] 我的收藏
  - [x] 站内私信
  
- [x] 动态相关
  - [x] 全部、投稿、番剧分类查看
  - [x] 动态评论查看
  - [x] 动态评论回复功能

- [x] 视频播放相关
  - [x] 双击快进/快退
  - [x] 双击播放/暂停
  - [x] 垂直方向调节亮度/音量
  - [x] 垂直方向上滑全屏、下滑退出全屏
  - [x] 水平方向手势快进/快退
  - [x] 全屏方向设置
  - [x] 倍速选择/长按2倍速
  - [x] 硬件加速（视机型而定）
  - [x] 画质选择（高清画质未解锁）
  - [x] 音质选择（视视频而定）
  - [x] 解码格式选择（视视频而定）
  - [x] 弹幕
  - [x] 字幕
  - [x] 记忆播放
  - [x] 视频比例：高度/宽度适应、填充、包含等
     
- [x] 搜索相关
  - [x] 热搜
  - [x] 搜索历史
  - [x] 默认搜索词
  - [x] 投稿、番剧、直播间、用户搜索
  - [x] 视频搜索排序、按时长筛选
    
- [x] 视频详情页相关
  - [x] 视频选集(分p)切换
  - [x] 点赞、投币、收藏/取消收藏
  - [x] 相关视频查看
  - [x] 评论用户身份标识
  - [x] 评论(排序)查看、二楼评论查看
  - [x] 主楼、二楼评论回复功能
  - [x] 评论点赞
  - [x] 评论笔记图片查看、保存

- [x] 设置相关
  - [x] 画质、音质、解码方式预设      
  - [x] 图片质量设定
  - [x] 主题模式：亮色/暗色/跟随系统
  - [x] 震动反馈(可选)
  - [x] 高帧率
  - [x] 自动全屏
  - [x] 横屏适配
- [ ] 等等

<br/>

## 下载

可以通过右侧release进行下载或拉取代码到本地进行编译

<br/>

## 声明

此项目（PiliPlus）是个人为了兴趣而开发，仅用于学习和测试，请于下载后24小时内删除。
所用API皆从官方网站收集，不提供任何破解内容。
在此致敬原作者：[guozhigq/pilipala](https://github.com/guozhigq/pilipala)
在此致敬上游作者：[orz12/PiliPalaX](https://github.com/orz12/PiliPalaX)
本仓库做了更激进的修改，感谢原作者的开源精神。

感谢使用


<br/>

## 致谢

- [bilibili-API-collect](https://github.com/SocialSisterYi/bilibili-API-collect)
- [flutter_meedu_videoplayer](https://github.com/zezo357/flutter_meedu_videoplayer)
- [media-kit](https://github.com/media-kit/media-kit)
- [dio](https://pub.dev/packages/dio)
- 等等

<br/>
<br/>
<br/>

## Star History

<a href="https://star-history.dera.page/#bggRGjQaUbCoE/PiliPlus&Date">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://star-history.dera.page/svg?repos=bggRGjQaUbCoE/PiliPlus&type=Date&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://star-history.dera.page/svg?repos=bggRGjQaUbCoE/PiliPlus&type=Date" />
   <img alt="Star History Chart" src="https://star-history.dera.page/svg?repos=bggRGjQaUbCoE/PiliPlus&type=Date" />
 </picture>
</a>

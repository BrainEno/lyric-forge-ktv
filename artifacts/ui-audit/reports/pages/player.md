# 页面审计：播放器族（QuickPlay / NowPlaying / 工程 Player / 全屏 KTV）

> 证据类型：静态代码审查。截图：无。四个页面文件合计约 3900 行。

## 1. QuickPlayScreen（`/quick-play`，1092 行）
用途：本地音乐即点即播。结构：AppBar「本地音乐」+ _PlayerWorkspace（_PlayerCard：封面/信息/Slider/传输控制）+ 队列 sheet。
问题：
- **条件路由语义不稳**：同一路由名依状态渲染三种页面（见 pages-and-routes.md R-3），用户从 Dashboard「打开音乐」点入时目标页不可预期。P2
- `_EmptyPlayer` 提供 FilledButton「选择音频文件」+ OutlinedButton「打开音乐库」双入口，合理；但空态封面占位样式与 dashboard/nowplaying 又各是一套（_Artwork:926）。P3
- 快捷操作：无键盘空格播放暂停（全应用仅歌词编辑器有快捷键）。P2（桌面核心场景）

## 2. NowPlayingScreen（`/now-playing`，667 行）
用途：正在播放沉浸页（隐藏全局播放条，app.dart suppressPlayerBar）。
- AppBar 标题「正在播放」；_NowPlayingCard 居中 + Slider + _TransportControls + _InfoChip。
- 与 QuickPlay 的 _Transport、_InfoChip **同名私有类重复实现**（now_playing:546/622 vs quick_play:997/970），样式可能漂移。P2

## 3. PlayerScreen（`/project/:id/player`，1476 行）
用途：工程 KTV 播放器（对照歌词）。结构：SliverAppBar（工程名）→ _PlayerWorkspace 双栏（_TransportPane | _LyricsPane），窄屏单栏；歌词区 _ScrollableLyrics / KTV 焦点模式 _KtvFocusLyrics/_FocusLyricLine；_AudioSourceSelector（原唱/伴奏切换）；showModalBottomSheet → KTV 入口（ktv_entry_sheet）。
亮点：
- 歌词区复用编辑器域组件，当前行高亮 `AppColors.accent.withAlpha(18)`（996 行），层级清晰。
- 加载/错误态完备（_LoadingState/_ErrorState 带重试）。
问题：
- **同文件两套传输控制**：`_TransportPane`(592) 与 `_PlaybackControls`(1246) 并存，职责切分不清。P2
- 全屏 KTV 入口藏在 showModalBottomSheet 的 KtvEntrySelection 流程中（281 行），可发现性依赖按钮文案。P3

## 4. ImmersiveKtvScreen（全屏 KTV，无独立路由）
结构：全屏歌词舞台（fullscreen_ktv_lyric_stage）+ 自动隐藏 _ControlLayer（180ms 渐隐，标题/退出/进度/三键/录音工具条）。
- 控制层自动隐藏符合 KTV 场景；退出按钮有 tooltip「退出全屏 KTV」。良好。
- 歌词舞台文字：当前行 headline w900 纯白，后续行 textSecondary，未唱 textTertiary —— **无逐字着色/扫光 Karaoke 效果**（仅行级高亮，逐字 timing 数据存在 word_timing 工具链却未用于舞台渲染——静态推断，需运行确认）。P2（KTV 核心卖点未发挥）
- 全屏背景未见使用应用图标红色元素。P3

## 共性改进
1. 收敛 4 套传输控制为 1 个可配置 TransportBar。
2. 桌面播放器补快捷键（空格/←/→/↑/↓）。
3. KTV 舞台评估逐字着色渲染（数据链路已存在）。

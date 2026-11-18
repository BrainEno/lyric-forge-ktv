# 页面与路由清单（E. 交付物）

> 证据类型：**静态代码审计**（沙箱无法运行 Flutter，见 `reports/environment-diagnostic.md`）。
> 路由源：`lib/core/navigation/routes.dart`；路由表：`lib/app/app_router.dart`；顶层导航：`lib/core/navigation/app_navigation_shell.dart` + `app_destinations.dart`。

## 1. 顶层导航结构（4 个目的地）

| 目的地 | 标签 | 图标（未选/选中） | 着陆路由 | 说明 |
|---|---|---|---|---|
| projects | 工程 | library_books | `/` | 导入歌曲、继续识别、打开工程 |
| library | 音乐库 | library_music | `/library` | 本机歌曲/艺人/专辑/收藏/歌单 |
| review | 校对 | spellcheck/fact_check | `/review` | 挑选需要校对的歌词 |
| settings | 设置 | settings | `/settings` | 播放、识别与存储设置 |

- 桌面宽屏（≥840 且非矮屏）：左侧 `NavigationRail`（≥1200 展开为 200dp 带标签，否则 88dp 折叠）。
- 窄屏/移动：底部 `NavigationBar`。
- 品牌位：Rail 顶部放了一个 **`Icons.graphic_eq_rounded` 原生图标**（`app_navigation_shell.dart:108`），不是应用图标。
- 沉浸式路由（`/project/:id/player` 全屏、传输页）不显示导航。

## 2. 路由 → 页面清单（19 条路由常量，15 个实际页面入口）

| 路由 | 页面（文件） | 用途 | 重要度 |
|---|---|---|---|
| `/`、`/dashboard` | `home/screens/dashboard_screen.dart` (1623 行） | 工作台首页：正在播放 Hero、后台任务卡、最近播放、最近工程 | ★★★★★ |
| `/import` | `import/screens/transcription_ready_import_screen.dart` → 内嵌 `import_audio_screen.dart` | 批量导入+识别就绪检查（两步合一：先 readiness，后文件选择） | ★★★★★ |
| `/library` | `player/screens/local_music_library_shell.dart` → `local_library_explorer_screen.dart` | 音乐库·歌曲 | ★★★★★ |
| `/library/artists` | 同上 shell → `local_artist_album_browser_screen.dart` (artists) | 音乐库·艺人 | ★★★☆ |
| `/library/albums` | 同上 shell → 同文件 (albums) | 音乐库·专辑 | ★★★☆ |
| `/collections` | 同上 shell → `local_collections_screen.dart` (favorites) | 音乐库·收藏 | ★★★☆ |
| `/playlists` | 同上 shell → 同文件 (playlists) | 音乐库·歌单 | ★★★☆ |
| `/quick-play` | `player/screens/quick_play_screen.dart` (1092 行） | 本地音乐快速播放器（条件路由：有远程流→NowPlaying；有历史→恢复） | ★★★★ |
| `/now-playing` | `player/screens/now_playing_screen.dart` | 正在播放（隐藏全局播放条） | ★★★★ |
| `/project/:id` | `project/screens/project_detail_screen.dart` (1451 行） | 工程详情：状态、进度、下一步操作面板、元数据 | ★★★★★ |
| `/project/:id/lyrics` | `lyrics/screens/lyric_editor_screen.dart` + `lyric_editor_content.dart` | 歌词校对编辑器（三栏：工具条+列表+检查器） | ★★★★★ |
| `/project/:id/player` | `player/screens/player_screen.dart` (1476 行） | KTV 工程播放器（含全屏沉浸式 `immersive_ktv_screen.dart`） | ★★★★★ |
| `/review` | `lyrics/screens/review_inbox_screen.dart` | 校对收件箱（跨工程待复核歌词列表） | ★★★★ |
| `/settings` | `settings/screens/settings_screen.dart` | 设置（AI 识别环境/冒烟测试/诊断） | ★★★★ |
| `/media-sharing` | `transfer/screens/desktop_media_transfer_hub_v2_screen.dart` | 桌面端：电脑↔手机传输中枢 | ★★★ |
| `/remote-library` | `transfer/screens/mobile_media_transfer_hub_screen.dart` | 移动端：传输中枢 | ★★★ |
| `/remote-library/browse` | `transfer/screens/mobile_remote_library_shell.dart` → 3 个子页 | 移动端浏览远程曲库 | ★★☆ |
| `/media-hub-scanner` | `transfer/screens/media_hub_qr_scanner_screen.dart` | 扫码配对 | ★★☆ |
| 未匹配兜底 | DashboardScreen | 未知路由回退到首页（无 404 页） | — |

### 条件/动态路由说明
- `/quick-play` 是**条件路由**（app_router.dart:82-108）：带 `PlayHistory` 参数 → 恢复该曲；当前播放是远程流 → 改挂 `NowPlayingScreen`；有本地播放 → QuickPlay；否则 → 音乐库。用户在同一个入口会看到三种页面。
- `/project/:id/*` 是动态段路由，`:id` 为工程 ID。

## 3. 无独立路由但承担重要功能的页面/组件

| 组件 | 文件 | 触发方式 | 说明 |
|---|---|---|---|
| ImmersiveKtvScreen | `player/screens/immersive_ktv_screen.dart` | PlayerScreen 内全屏按钮 | 全屏 KTV 舞台（控制层自动隐藏） |
| GlobalPlayerBar | `player/widgets/global_player_bar.dart` | 桌面常驻底部 | 全局播放条（桌面 chrome） |
| MobileGlobalPlayerBar | `player/widgets/mobile_global_player_bar.dart` | 移动常驻 | 全局迷你播放条 |
| GlobalTranscriptionQueueBar | `transcription/widgets/global_transcription_queue_bar.dart` | 桌面常驻（播放条上方） | 后台识别队列条 |
| LocalMusicLibraryShell 五个分区 | 见上 | shell 内 ChoiceChip 切换 + IndexedStack | 歌曲/艺人/专辑/收藏/歌单共享一个 shell |

## 4. 弹窗（Dialog）清单 — 44 个文件、57 处 showDialog 调用

### 歌词校对域（29 个对话框/弹窗文件 — 密度最高）
`lyric_proofread_v2_dialog`、`reference_alignment_dialog`、`reference_alignment_review`、`reference_proofread_review_dialog`、`reference_proofread_timing_review_dialog`、`reference_alignment_backup_dialog`、`chinese_script_unification_dialog`、`lyric_asr_loop_dialog`、`lyric_find_replace_dialog`、`lyric_missed_repeat_dialog`、`lyric_pace_check_dialog`、`lyric_repetition_consistency_dialog`、`lyric_span_recognition_dialog`、`lyric_structure_dialog`、`lyric_tap_sync_dialog`、`lyric_text_cleanup_dialog`、`lyric_timeline_repair_dialog`、`lyric_timing_shift_dialog`、`lyric_word_tap_dialog`、`lyric_word_timing_check_dialog`、`lyric_word_timing_edit_dialog`、`project_asr_snapshot_dialog`、`project_chunk_asr_snapshot_dialog`、`project_save_conflict_dialog`、`timing_evidence_import_dialog`、`unsaved_lyric_edits_dialog`、`lyric_export_dialog`、`lyric_batch_text_edit`(工具路由）、`reference_alignment_result_comparison`(sheet)

→ 其中 **20 个校对工具统一收敛在 `LyricProofreadMenuButton` 一个菜单内**（见组件清单）。

### 识别/设置域
`asr_runtime_setup_dialog`（识别环境安装，981 行）、`transcription_config_dialog`（识别配置，736 行）、`ai_transcription_settings_section` 内嵌确认弹窗（迁移/删除模型）

### 播放/曲库域
`local_media_metadata_dialog`（编辑歌曲资料与封面）、`playback_queue_playlist_action`（加入播放列表）、`ktv_entry_sheet`、`ktv_microphone_sheet`、`ktv_take_history_sheet`、`ktv_take_result_sheet`（4 个 KTV BottomSheet）

### 传输域
传输页内 `开启加密的网络共享？` 确认框、安全提示卡等

## 5. BottomSheet 清单（11 处 showModalBottomSheet）

歌词编辑器行检查器（`lyric_editor_content._showInspectorSheet`）、对齐结果对比、对齐复核、KTV 入口/麦克风/历史/结果（×4）、NowPlaying 队列、QuickPlay 队列、远程分组曲库操作。

## 6. 已发现的结构问题（静态证据）

| # | 现象 | 位置 | 级别 |
|---|---|---|---|
| R1 | **死代码页面**：`RemoteMediaLibraryScreen`（632 行）无任何引用 | `transfer/screens/remote_media_library_screen.dart` | P2 |
| R2 | 兜底路由静默回退首页，无 404/提示 | app_router.dart default 分支 | P3 |
| R3 | `/quick-play` 一入口三页面，语义不稳定 | app_router.dart:82 | P2（交互） |
| R4 | `routes.dart` 中 `import`、`review` 与旧注释提到的页面映射关系需人工对照才能确认 | routes.dart | P3 |

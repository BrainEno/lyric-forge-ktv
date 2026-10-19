# Work Log Archive

> Navigation only. The full text of every entry lives in `docs/log/entries/<file>.md`;
> the newest entries are listed in [work_log.md](work_log.md). History is preserved verbatim and is never deleted.

## 2025-04 | App skeleton and playback basics

- [2025-04-23 22:45] Phase 1.5: 实现快速播放模式 `feat: add quick play mode with play history` ([entry](log/entries/2025-04-23-2245-add-quick-play-with-history.md))
- [2025-04-22 22:30] Phase 1.3 Task 6: 重构 PlayerScreen 接入真实音频播放 `feat: refactor PlayerScreen with real audio playback and source switching` ([entry](log/entries/2025-04-22-2230-player-screen-real-audio-playback.md))
- [2025-04-22 21:30] Phase 1.3 Task 1-5: 接入 just_audio 音频播放基础设施 `feat: add just_audio playback service layer with source switching` ([entry](log/entries/2025-04-22-2130-add-just-audio-playback-service.md))
- [2025-04-22 20:00] 实现 LyricEditor 歌词编辑器与 Player 播放器 `feat: add lyric editor and player with synced lyrics` ([entry](log/entries/2025-04-22-2000-add-lyric-editor-and-player.md))
- [2025-04-22 19:25] 完成导入流程占位与 ProjectDetail 详情页 `feat: add import flow and project detail screen` ([entry](log/entries/2025-04-22-1925-add-import-flow-and-project-detail.md))
- [2025-04-22 19:15] 添加 ProjectRepository 抽象与内存实现 `feat: add project repository with memory implementation` ([entry](log/entries/2025-04-22-1915-add-project-repository-memory-impl.md))
- [2025-04-22 19:05] 接入 AppTheme 和 AppRouter，完成 Dashboard 产品入口 `feat: wire up theme and router, build dashboard entry point` ([entry](log/entries/2025-04-22-1905-wire-theme-router-dashboard.md))

## 2026-10-09 | Lyric timeline, LRC export and KTV microphone

- [2026-10-09 15:42] 持久化 KTV 麦克风输入设备选择 `Persist KTV microphone input choice` ([entry](log/entries/2026-10-09-1542-persist-ktv-microphone-input-choice.md))
- [2026-10-09 15:08] KTV 麦克风设备选择接入控制面板 `Expose KTV microphone device picker` ([entry](log/entries/2026-10-09-1508-ktv-microphone-device-picker.md))
- [2026-10-09 14:59] 增加 KTV 麦克风输入设备枚举与热切换底层 `Add KTV microphone input device switching` ([entry](log/entries/2026-10-09-1459-ktv-microphone-input-device-switching.md))
- [2026-10-09 12:58] 打通 KTV 人声录音、对齐保护与离线混音导出 `Add aligned KTV take recording and mix export` ([entry](log/entries/2026-10-09-1258-aligned-ktv-take-recording-and-mix-export.md))
- [2026-10-09 12:36] 接入 KTV 实时麦克风监听、独立音量与延迟控制 `Add low-latency KTV microphone monitoring` ([entry](log/entries/2026-10-09-1236-low-latency-ktv-microphone-monitoring.md))
- [2026-10-09 12:14] 增加播放器麦克风 KTV 入口与伴唱模式 `Add microphone KTV entry and backing choice` ([entry](log/entries/2026-10-09-1214-microphone-ktv-entry-and-backing-mode.md))
- [2026-10-09 12:03] 固定 LRC 导出的有效播放时间语义 `Export LRC with effective playback timestamps` ([entry](log/entries/2026-10-09-1203-lrc-effective-playback-timestamps.md))
- [2026-10-09 11:57] 让播放器返回校对后立即读取最新歌词 `Refresh player lyrics after timeline editing` ([entry](log/entries/2026-10-09-1157-refresh-player-lyrics-after-edit.md))
- [2026-10-09 11:52] 让普通同步歌词随播放自动滚动 `Auto-scroll synced lyrics with playback` ([entry](log/entries/2026-10-09-1152-auto-scroll-synced-lyrics.md))
- [2026-10-09 11:46] 打通歌词时间轴校对与 LRC 导出切片 `Add synced lyric timeline editing and LRC export` ([entry](log/entries/2026-10-09-1146-synced-lyric-timeline-and-lrc-export.md))

## 2026-10-19 | ASR model download, proxy and setup

- [2026-10-19 16:11] 允许代理独立保存并在对话框内提示缺项 `Allow saving ASR proxy independently` ([entry](log/entries/2026-10-19-1611-save-asr-proxy-independently.md))
- [2026-10-19 15:55] 立即持久化安装流程中的高级识别设置 `Persist ASR advanced settings immediately` ([entry](log/entries/2026-10-19-1555-persist-asr-advanced-settings-immediately.md))
- [2026-10-19 15:44] 为 ASR 模型下载接入代理与连通性检查 `Add proxy support for ASR downloads` ([entry](log/entries/2026-10-19-1544-asr-download-proxy-and-connectivity-check.md))
- [2026-10-19 15:30] 区分 ASR 环境准备与文件下载进度 `Clarify ASR setup and download progress` ([entry](log/entries/2026-10-19-1530-asr-setup-vs-download-progress.md))
- [2026-10-19 15:17] 修复 ASR 模型下载超时与自动续传 `Retry stalled ASR model downloads` ([entry](log/entries/2026-10-19-1517-retry-stalled-asr-model-downloads.md))

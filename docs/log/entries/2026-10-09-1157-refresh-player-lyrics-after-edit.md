# [2026-10-09 11:57] 让播放器返回校对后立即读取最新歌词

- Scope: 播放器进入歌词校对器时等待编辑路由返回；用户保存并退出后重新读取当前工程 manifest，使纠正后的歌词文本、时间轴和全局 offset 立即成为当前播放器的同步歌词来源，同时保留现有音频播放会话与播放位置。
- Files: `lib/features/player/presentation/screens/player_screen.dart`, `lib/features/transcription/data/services/local_project_transcription_workflow.dart`
- Validation:
  - `flutter analyze --no-fatal-infos --no-fatal-warnings` => success
  - `flutter test` => success
- Notes: 修复了播放器长期持有进入编辑器前 `ProjectManifest` 快照的问题；刷新仅重新读取工程数据，不重新创建或重启当前播放会话。
- Commit: `Refresh player lyrics after timeline editing`

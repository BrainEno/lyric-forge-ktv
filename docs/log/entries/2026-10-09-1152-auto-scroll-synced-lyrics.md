# [2026-10-09 11:52] 让普通同步歌词随播放自动滚动

- Scope: 将普通播放器同步歌词列表改为带 `ScrollController` 的跟播视图；当前歌词行变化或 seek 后平滑滚动到视口上中部，KTV 焦点模式及播放器状态机保持不变。
- Files: `lib/features/player/presentation/screens/player_screen.dart`, `lib/features/transcription/data/services/local_project_transcription_workflow.dart`
- Validation:
  - `flutter analyze --no-fatal-infos --no-fatal-warnings` => success
  - `flutter test` => success
- Notes: 当前滚动使用估算行高定位，目标是稳定保证当前行回到可视区；长歌词行可能不是严格像素居中，但不会改变时间轴或 seek 语义。
- Commit: `Auto-scroll synced lyrics with playback`

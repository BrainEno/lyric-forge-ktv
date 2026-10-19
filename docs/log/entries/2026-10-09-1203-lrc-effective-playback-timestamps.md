# [2026-10-09 12:03] 固定 LRC 导出的有效播放时间语义

- Scope: 导出 LRC 时把工程 `globalOffset` 烘焙到每行时间戳，避免不同播放器对 `[offset]` 正负方向解释不一致；工程内仍保留独立 offset 供编辑。
- Files: `lib/features/lyrics/data/services/local_lyric_file_export_service.dart`, `test/local_lyric_file_export_service_test.dart`, `docs/lyric-export-format.md`, `lib/features/transcription/data/services/local_project_transcription_workflow.dart`
- Validation:
  - `flutter analyze --no-fatal-infos --no-fatal-warnings` => success
  - `flutter test` => success
- Notes: 用户导出的 LRC 是最终播放时间轴；重新导入后播放对齐保持一致，但 offset 分解会被压平。LyricForge project manifest 继续作为无损编辑主文件；负的最终时间戳会钳制到 `00:00.000`。
- Commit: `Export LRC with effective playback timestamps`

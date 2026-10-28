# [2026-10-09 11:46] 打通歌词时间轴校对与 LRC 导出切片

- Scope: 将 ASR 识别结果明确标记为可编辑的 `lyricforge-timeline-v1` 草稿；在歌词校对页增加跟随播放滚动、使用当前播放位置校准选中行起止时间、保留逐行文本纠错与微调，并新增 UTF-8 LRC 导出能力。
- Files: `lib/features/transcription/data/services/local_project_transcription_workflow.dart`, `lib/features/lyrics/presentation/screens/lyric_editor_screen.dart`, `lib/features/lyrics/domain/services/lyric_file_export_service.dart`, `lib/features/lyrics/data/services/local_lyric_file_export_service.dart`, `lib/core/services/service_locator.dart`, `test/local_lyric_file_export_service_test.dart`, `docs/lyric-export-format.md`
- Validation:
  - `flutter analyze --no-fatal-infos --no-fatal-warnings` => success
  - `flutter test` => success
- Notes: 用户导出格式固定为 UTF-8 LRC，使用 `[mm:ss.SSS]` 行起点与独立 `[offset:<ms>]`；工程 manifest 继续保存精确结束时间、置信度、副歌和复核元数据。导出测试覆盖毫秒时间戳、offset、空行过滤以及 LRC 导出后重新导入的 round-trip。
- Commit: `Add synced lyric timeline editing and LRC export`

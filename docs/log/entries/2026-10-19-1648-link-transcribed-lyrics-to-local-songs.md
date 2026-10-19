# [2026-10-19 16:48] 修复识别歌词未关联到本地歌曲

- Scope: 本地识别完成后，将歌词工程 ID 持久化关联到原音频的本地媒体元数据，并刷新播放队列中对应歌曲的 `hasLyrics` 状态，使当前播放和后续打开歌曲时都能解析、显示识别歌词；歌词文件导入复用相同关联逻辑。
- Files: `lib/features/player/domain/services/playback_lyrics_project_linker.dart`, `lib/features/transcription/data/services/local_project_transcription_workflow.dart`, `lib/features/player/presentation/widgets/local_song_lyrics_import_action.dart`, `lib/core/services/service_locator.dart`, `test/features/player/playback_lyrics_project_linker_test.dart`, `docs/work_log.md`
- Validation:
  - `flutter test test\features\player\playback_lyrics_project_linker_test.dart test\features\player\now_playing_lyrics_project_action_test.dart` => All tests passed
  - `flutter analyze --no-fatal-infos`（本次修改的 5 个 Dart 文件）=> success；11 条既有 info，无错误/警告
  - `dart format --output=none --set-exit-if-changed`（新增服务及测试）=> success
  - `git diff --check` => success
- Notes: AXTree 报错未证明是歌词无法显示的原因；本次修复了识别工程与本地歌曲之间缺失的 `linkedProjectId` 关联。未运行全量测试或 GUI 手动验证。
- Commit: `Link transcribed lyrics to local songs`

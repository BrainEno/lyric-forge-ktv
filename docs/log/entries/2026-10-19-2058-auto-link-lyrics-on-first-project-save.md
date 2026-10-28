# [2026-10-19 20:58] 收尾歌词首次写入工程的自动关联切片

- Scope: 完成上一会话遗留的未提交改动：歌词编辑器保存首次写入歌词时（`updateProject` 中 `lyricDocument` 由无变有），自动把工程关联到对应音频的本地歌曲元数据并刷新播放队列，令编辑/导入歌词的保存路径与识别工作流共享同一关联语义。同时修掉 2 处多余 `!` 告警、格式化 `service_locator.dart` 的非标准缩进，并补齐自动关联的定向测试。
- Files: `lib/features/project/data/repositories/file_project_repository.dart`, `lib/core/services/service_locator.dart`, `test/file_project_repository_test.dart`
- Validation:
  - `flutter analyze --no-fatal-infos lib/features/project/data/repositories/file_project_repository.dart test/file_project_repository_test.dart lib/core/services/service_locator.dart` => 无错误；仅剩该文件 4 条既存 info
  - `flutter test test/file_project_repository_test.dart test/features/player/playback_lyrics_project_resolver_test.dart test/features/player/playback_lyrics_project_linker_test.dart test/features/player/now_playing_lyrics_project_action_test.dart` => All 18 tests passed
  - `dart format lib/features/project/data/repositories/file_project_repository.dart test/file_project_repository_test.dart lib/core/services/service_locator.dart` => formatted clean
  - `git diff --check` => success（仅 LF→CRLF 提示）
- Notes: 关联为 fire-and-forget（`unawaited`），仅在歌词从无到有时触发，重复编辑不会反复重链；测试用 `pumpEventQueue` 保证异步关联可断言。同一音频若已有指向其他工程的关联，再次新工程挂歌词会静默覆盖为最新工程——冲突确认提示留给后续 A3 切片。播放条目状态刷新复用 linker 既有行为。
- Commit: `Auto-link lyrics on first project save`

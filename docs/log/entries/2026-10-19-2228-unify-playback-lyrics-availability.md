# [2026-10-19 22:28] 统一各播放面的歌词可用性判定

- Scope: 队列条目上的 `hasLyrics` 只是入队时写入的缓存：歌词工程被删除后它不会回撤，工程在入队之后才生成时也不会补上，于是播放器底栏、快速播放与 Now Playing 对同一首歌的"打开歌词 / 导入歌词"判断会互相矛盾。本切片把解析结果结构化为 `PlaybackLyricsResolution`（工程 id、是否真的带有歌词、是否修复或清除死链），新增 `resolveAndSyncPlaybackLyrics` 在解析后把权威结果回写队列条目，并在应用壳层挂载 `PlaybackLyricsAvailabilitySync`，随当前条目变化自动同步；歌词入口点击时也走同一解析，因此死链会被清除并立即反映到所有播放面。
- Files: `lib/features/player/domain/services/playback_lyrics_project_resolver.dart`, `lib/features/player/domain/services/playback_lyrics_availability.dart`, `lib/features/player/presentation/widgets/playback_lyrics_availability_sync.dart`, `lib/main.dart`, `lib/features/player/presentation/widgets/now_playing_lyrics_project_action.dart`, `lib/features/player/presentation/widgets/local_song_lyrics_import_action.dart`, `test/features/player/playback_lyrics_project_resolver_test.dart`, `test/features/player/playback_lyrics_availability_test.dart`, `docs/decisions.md`, `docs/work_log.md`, `docs/work_log_archive.md`, `docs/work_log_index.md`, `docs/handoff.md`
- Validation:
  - `flutter analyze --no-pub --no-fatal-infos` => 0 error / 0 warning（149 条样式 info，与切片前一致）
  - `flutter test --no-pub --reporter expanded` => All tests passed（319 通过 / 2 跳过，新增 9 条）
  - `flutter test test/features/player/playback_lyrics_availability_test.dart` => 7 passed（含壳层同步的 widget 测试）
  - `flutter test test/features/player/playback_lyrics_project_resolver_test.dart test/features/player/playback_lyrics_project_linker_test.dart test/features/player/now_playing_lyrics_project_action_test.dart` => 20 passed
  - `powershell -File scripts/quality_gate.ps1 -SkipPubGet` => Repository quality gate (all) passed
  - `dart tool/work_log.dart check` => success
- Notes: 解析不再依赖条目上的 `hasLyrics` 缓存（远程流除外），所以入队后才生成的歌词工程也能被发现；媒体元数据与工程列表都已在内存缓存，按当前条目解析的成本可控。队列写回与自愈写失败都只静默跳过，不阻塞播放；远程流的 `hasLyrics` 由远端目录维护，同步器直接跳过。歌词入口在找不到歌词工程时仍会复用拥有该音频的草稿工程，避免导入时产生重复工程。已知遗留：工程仓库读取异常会被当作"没有工程"，仍可能清除链接（既有行为，本轮未改，后续硬化）。另外当前 SDK 的 `dart format` 会启用新的 tall style，对既有文件是整篇重排，为免把格式噪音混进本切片，未对既有文件执行格式化。
- Commit: `Unify playback lyrics availability across surfaces`

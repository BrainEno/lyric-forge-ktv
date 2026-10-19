# [2026-10-19 20:33] 歌词关联三级解析与死链自愈

- Scope: 普通本地歌曲在播放时解析歌词工程不再只依赖元数据里的 `linkedProjectId`：若关联已失效或不存在，自动按音频路径兜底匹配仍存在歌词的工程并回写关联；确认无任何工程匹配时清除死链并撤回 `hasLyrics` 标记。这样工程被删除、元数据丢失或文件重新导入后，再次播放同一首歌仍能自动找回识别歌词，同时不会用可写失败阻塞播放。
- Files: `lib/features/player/domain/services/playback_lyrics_project_resolver.dart`, `test/features/player/playback_lyrics_project_resolver_test.dart`
- Validation:
  - `flutter analyze --no-fatal-infos lib/features/player/domain/services/playback_lyrics_project_resolver.dart test/features/player/playback_lyrics_project_resolver_test.dart` => No issues found
  - `flutter test test/features/player/playback_lyrics_project_resolver_test.dart test/features/player/playback_lyrics_project_linker_test.dart test/features/player/now_playing_lyrics_project_action_test.dart test/file_project_repository_test.dart` => All 15 tests passed
  - `dart format lib/features/player/domain/services/playback_lyrics_project_resolver.dart test/features/player/playback_lyrics_project_resolver_test.dart` => formatted clean
  - `git diff --check` => success（仅 Windows LF→CRLF 提示）
- Notes: 解析顺序为 item.projectId → persisted linkedProjectId → 同路径工程扫描；路径兜底只接受 `hasLyrics` 的工程，草稿工程不会被误当成可播放歌词。同 id 在兜底扫描中再次命中时不重写（避免无意义刷新时间戳）。自愈写失败仅静默跳过，元数据存储被摘除时解析仍可只读完成。远程流与未带歌词标记的条目维持原语义。播放条目队列里的 `hasLyrics` 标记在清除死链后不会立即回撤，需经 linker 重链或重新入队刷新，统一各播放面状态留给下一切片：届时将盘点各播放入口是否统一走 resolver。另外工作区存在上次会话遗留的未提交改动（`updateProject` 首次写入歌词时自动关联 + service_locator 配线），2 处多余 `!` warning；归属用户既有工作，未合并进本切片提交。
- Commit: `Add fallback resolution and self-healing for lyric links`

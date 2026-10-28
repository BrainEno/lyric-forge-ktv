# [2026-10-19 21:22] 入队时同步歌词状态，统一各播放面判定

- Scope: 本地歌曲从曲库/快速播放入队时，播放会话原先只应用标题、歌手、封面用户覆盖，从不读取歌词关联，导致标识过的歌曲在新会话中队列条目仍是 `hasLyrics: false`，快速播放页面显示"未添加歌词"、入口按钮退化成"导入歌词"。现在入队增强阶段直接按音频路径读取元数据里的 `linkedProjectId`，非空即置 `hasLyrics: true`，与音乐库列表、Now Playing、沉浸式 KTV 共用同一关联判定，不再要求每个播放面各自重跑解析。
- Files: `lib/features/player/data/services/default_playback_session_service.dart`, `test/local_media_metadata_playback_test.dart`
- Validation:
  - `flutter analyze --no-fatal-infos lib/features/player/data/services/default_playback_session_service.dart test/local_media_metadata_playback_test.dart` => No issues found
  - `flutter test test/local_media_metadata_playback_test.dart test/embedded_metadata_playback_priority_test.dart` => All 8 tests passed
  - `flutter test test/features/player/playback_lyrics_project_resolver_test.dart test/features/player/playback_lyrics_project_linker_test.dart test/features/player/now_playing_lyrics_project_action_test.dart test/file_project_repository_test.dart` => All 18 tests passed（歌词链路回归）
  - `dart format` + `git diff --check` => clean
- Notes: 用户覆盖与歌词标志共用一次 `_withLocalMediaMetadata` 读仓，未增加新依赖或接线（base session 已持有 metadata 仓）。`projectId` 不被复制，普通本地歌的播放行为保持不变；工程播放走已有 early-return 分支不受影响。远程流与解析死链后长驻队列条目的刷新策略维持不变，跨设备歌词跟随（阶段 B）与本切片无耦合。
- Commit: `Sync lyrics flag into playback queue enrichment`

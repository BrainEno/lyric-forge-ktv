# [2026-10-09 12:14] 增加播放器麦克风 KTV 入口与伴唱模式

- Scope: 在已有同步歌词的播放器顶部增加麦克风 KTV 入口；进入前让用户选择“原唱伴唱”或“纯伴奏”，选择后切换音源并直接进入全屏 KTV。全屏 KTV 中继续允许在这两种演唱音轨之间切换，隔离人声轨不作为 KTV 背景音源暴露。
- Files: `lib/features/player/domain/models/ktv_backing_mode.dart`, `lib/features/player/presentation/screens/player_screen.dart`, `test/features/player/ktv_backing_mode_test.dart`
- Validation:
  - `flutter analyze --no-fatal-infos --no-fatal-warnings` => success
  - `flutter test` => success
- Notes: “原唱伴唱”映射现有 original mix，“纯伴奏”映射 instrumental stem；底层 `switchSource` 会保留当前播放位置和播放状态。没有 instrumental 时纯伴奏选项明确禁用并提示先生成伴奏轨。
- Commit: `Add microphone KTV entry and backing choice`

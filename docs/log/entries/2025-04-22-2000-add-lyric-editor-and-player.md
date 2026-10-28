# [2025-04-22 20:00] 实现 LyricEditor 歌词编辑器与 Player 播放器

- Scope: 完成 LyricEditorScreen 手动歌词编辑功能（添加/删除/修改歌词行、时间戳调整、副歌标记、全局偏移调节）和 PlayerScreen 播放器骨架（进度条控制、播放/暂停、歌词同步高亮、点击歌词跳转）。形成"编辑→预览"闭环。
- Files: `lib/features/lyrics/presentation/screens/lyric_editor_screen.dart`, `lib/features/player/presentation/screens/player_screen.dart`
- Validation:
  - `flutter analyze` => No issues found
- Notes: LyricEditor 支持行级时间戳编辑（+/-0.1s/1s）、副歌高亮显示、空行添加。Player 使用 Timer 模拟播放进度，歌词自动高亮当前行。均为占位实现，未接入真实音频播放。
- Commit: `feat: add lyric editor and player with synced lyrics`

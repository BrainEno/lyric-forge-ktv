# [2025-04-22 22:30] Phase 1.3 Task 6: 重构 PlayerScreen 接入真实音频播放

- Scope: 将 PlayerScreen 从 Timer 模拟播放重构为使用 just_audio 的真实音频播放器。包含：1) 接入 AudioPlayerService 服务；2) 从音频文件获取真实时长和进度；3) 添加音源切换 UI（原声/伴奏/人声按钮）；4) 实现带缓冲显示的进度条；5) 歌词同步从真实播放位置获取；6) 添加加载和缓冲状态视觉反馈。
- Files: `lib/features/player/presentation/screens/player_screen.dart` (重写), `lib/core/services/service_locator.dart` (添加 audioPlayerService)
- Validation:
  - `flutter analyze` => No issues found
- Notes: PlayerScreen 现在支持播放真实的 MP3/FLAC/WAV/M4A 文件。新增 _ProgressBar 组件显示缓冲进度和播放进度，_AudioSourceSelector 组件支持切换音源（仅显示可用音源），_PlaybackControls 显示缓冲加载动画。UI 保持 Spotify 风格暗色主题。Phase 1.3 全部完成，播放器已可正常使用。
- Commit: `feat: refactor PlayerScreen with real audio playback and source switching`

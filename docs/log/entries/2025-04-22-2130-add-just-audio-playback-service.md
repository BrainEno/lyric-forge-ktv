# [2025-04-22 21:30] Phase 1.3 Task 1-5: 接入 just_audio 音频播放基础设施

- Scope: 添加 just_audio 依赖并构建完整的音频播放服务层，为 Phase 1.3 PlayerScreen 重构提供基础。包含：1) 添加 just_audio/audio_session 依赖；2) 扩展 AudioAsset 添加 AudioSourceType 枚举和扩展方法；3) 创建 PlaybackState 播放状态模型；4) 定义 AudioPlayerService 领域接口；5) 实现 JustAudioPlayerService 适配器；6) 注册到 ServiceLocator。
- Files: `pubspec.yaml`, `lib/features/project/domain/models/audio_asset.dart`, `lib/features/player/domain/models/playback_state.dart` (新建), `lib/features/player/domain/services/audio_player_service.dart` (新建), `lib/features/player/data/services/just_audio_player_service.dart` (新建), `lib/core/services/service_locator.dart`
- Validation:
  - `flutter analyze` => No issues found
  - `flutter pub get` => Got dependencies
- Notes: 完整实现音频播放服务抽象，支持原声/伴奏/人声三种音源切换。JustAudioPlayerService 包装 just_audio 库，提供统一的 PlaybackState 状态流。AudioAsset 新增扩展方法简化音源选择和可用性检查。目前仅为基础设施，PlayerScreen 重构将在 Task 6 完成。
- Commit: `feat: add just_audio playback service layer with source switching`

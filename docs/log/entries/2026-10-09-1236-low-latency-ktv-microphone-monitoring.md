# [2026-10-09 12:36] 接入 KTV 实时麦克风监听、独立音量与延迟控制

- Scope: 为全屏 KTV 增加真实麦克风输入和低延迟监听；麦克风 PCM16 由 `record` 捕获，经可测试的增益/延迟 DSP 后送入 `flutter_soloud` 输出。新增麦克风开关、电平表、0–200% 麦克风增益、独立歌曲音量和 0–250ms 监听附加延迟控制；退出全屏 KTV 自动关闭监听。
- Files: `lib/features/player/domain/models/ktv_microphone_state.dart`, `lib/features/player/domain/services/ktv_microphone_service.dart`, `lib/features/player/data/services/pcm_delay_line.dart`, `lib/features/player/data/services/record_soloud_ktv_microphone_service.dart`, `lib/features/player/presentation/screens/player_screen.dart`, `lib/features/player/data/services/just_audio_player_service.dart`, `lib/core/services/service_locator.dart`, Android/iOS/macOS 麦克风权限配置、Flutter generated plugin registrants, `pubspec.yaml`, `pubspec.lock`, `test/features/player/ktv_microphone_signal_test.dart`
- Validation:
  - `flutter pub get` => success with existing `mobile_scanner`
  - `flutter analyze --no-fatal-infos --no-fatal-warnings` => success
  - `flutter test test/features/player/ktv_microphone_signal_test.dart` => success
  - `flutter test` => success
  - `flutter build windows --debug` => success
  - `flutter build macos --debug` => success
- Notes: 早期评估的 `audio_io >=0.3` 与现有 `mobile_scanner 7.4.x` 在 `web` 依赖上不可共存，因此改用 `record 6.2.1 + flutter_soloud 5.1.2`，不降级扫码功能。当前“延迟补偿”只允许增加监听延迟，不伪装成能消除硬件已有延迟；UI 会展示 SoLoud 报告的输出延迟（可用时）。本切片不把仅麦克风录制冒充完整 KTV 成品录音，混合录音留给后续共享混音/离线合成链路。
- Commit: `Add low-latency KTV microphone monitoring`

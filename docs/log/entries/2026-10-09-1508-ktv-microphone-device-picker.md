# [2026-10-09 15:08] KTV 麦克风设备选择接入控制面板

- Scope: 将麦克风输入设备发现/热切换能力接入全屏 KTV 的“麦克风与演唱音量”面板；用户可在“系统默认”和检测到的具体麦克风之间选择并手动刷新。录音 take、麦克风启动或设备刷新期间会锁定设备操作，避免中途换输入源破坏录音一致性；同时修正 `record 6.2.1` 输入设备适配器误读不存在的采样率属性。
- Files: `lib/features/player/data/services/record_soloud_ktv_microphone_service.dart`, `lib/features/player/presentation/screens/player_screen.dart`, `docs/work_log.md`
- Validation:
  - `flutter analyze --no-fatal-infos --no-fatal-warnings` => success
  - `flutter test test/features/player/ktv_microphone_signal_test.dart` => success
  - `flutter test` => success
- Notes: `record 6.2.1` 当前只提供输入设备 ID/名称，适配器因此保留领域模型的采样率扩展位但不虚构数据，UI 只显示真实设备名称。设备选择仍只保存于当前应用会话，持久化留给后续独立切片；真实 Windows/macOS 多麦克风拔插、蓝牙/USB 切换仍需物理设备 E2E 验证。
- Commit: `Expose KTV microphone device picker`

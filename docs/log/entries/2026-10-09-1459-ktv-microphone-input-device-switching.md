# [2026-10-09 14:59] 增加 KTV 麦克风输入设备枚举与热切换底层

- Scope: 在现有 KTV 麦克风服务中增加输入设备枚举、稳定 ID 选择、系统默认回退与监听中热切换能力；`record.InputDevice` 仅保留在 data 层，domain 状态只暴露可序列化的设备 ID、名称和采样率信息。应用服务初始化时会预加载设备列表，后续 UI 可以直接绑定同一状态流。
- Files: `lib/core/services/service_locator.dart`, `lib/features/player/domain/models/ktv_microphone_state.dart`, `lib/features/player/domain/services/ktv_microphone_service.dart`, `lib/features/player/data/services/record_soloud_ktv_microphone_service.dart`, `test/features/player/ktv_microphone_signal_test.dart`
- Validation:
  - `flutter pub get` in existing PR check => success
  - `flutter analyze lib/core/services/service_locator.dart ...` in existing PR check => success
  - `flutter test test/features/transcription/resilient_asr_runtime_manager_test.dart` regression check => success
- Notes: 新增的 player focused tests 已写入 `ktv_microphone_signal_test.dart`，但当前仓库的 path-scoped PR workflow 不会自动执行 player tests，因此本切片没有声称 focused player test 已在 CI 中跑过。物理麦克风设备枚举/拔插/热切换仍需 Windows/macOS 真机验证；下一切片只需把现有 KTV 麦克风面板绑定到这些服务 API，并在 take 录音中禁用设备切换。
- Commit: `Add KTV microphone input device switching`

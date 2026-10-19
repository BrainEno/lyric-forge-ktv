# [2026-10-09 15:42] 持久化 KTV 麦克风输入设备选择

- Scope: 将全屏 KTV 中选择的麦克风设备 ID 持久化到 Application Support JSON；应用下次启动时在设备枚举前恢复首选输入。若设备已拔出、ID 失效或配置文件损坏，则安全回退系统默认输入，并清除陈旧偏好。
- Files: `lib/features/player/domain/services/ktv_microphone_preference_store.dart`, `lib/features/player/data/services/file_ktv_microphone_preference_store.dart`, `lib/features/player/data/services/record_soloud_ktv_microphone_service.dart`, `lib/core/services/service_locator.dart`, `test/features/player/ktv_microphone_preference_store_test.dart`, `docs/work_log.md`
- Validation:
  - `flutter analyze --no-fatal-infos --no-fatal-warnings` => success
  - microphone preference + signal focused tests => success
  - `flutter test` => success
- Notes: 只持久化输入设备选择，不自动恢复监听开关、麦克风增益或监听延迟；偏好文件读写失败不会阻断麦克风监听/录音。真实 Windows/macOS USB、蓝牙设备跨重启 ID 稳定性仍需物理设备 E2E 验证。
- Commit: `Persist KTV microphone input choice`

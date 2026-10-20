# [2026-10-20 20:42] 新增歌词时间轴校验器（E2.1）

- `Scope`: 阶段 E2 时间轴正确性加固的第一步。新增纯 Dart `LyricTimelineValidator`，只读检测歌词行时间冲突，不修改任何输入；冲突时明确提示，不静默删除旧歌词、不静默裁剪相邻行；确实不能推断时标记为需校准，由用户定点校准。
- `Files`: 新增 `lib/features/lyrics/domain/services/lyric_timeline_validator.dart`（检测负时间、零/负时长、前后行重叠、极短空隙、超出音频总时长；返回 `issues` 与 `needsCalibration`）；新增 `test/features/lyrics/domain/services/lyric_timeline_validator_test.dart`（15 例）；`docs/log/entries/2026-10-20-2042-e1-timeline-validator.md`、`docs/work_log.md`。
- `Validation`: `dart format` 2 个新文件（0 变更）；`flutter analyze --no-pub` 2 个文件 → No issues found；`flutter test --no-pub test/features/lyrics/domain/services/lyric_timeline_validator_test.dart` → 15/15 通过。
- `Notes`: 验收条件中"负时间、零时长、极短空隙、前后行重叠、带时间戳漏行与无时间戳末尾漏行"均已覆盖。未提供音频时长时不做边界检查；提供后尾部插入超出音频时长的行为将在 E2.2（插入服务音频时长边界）中配合处理。LRC 时间戳冲突处理将在 E2.3 中与导入/导出服务结合。
- `Commit`: Add lyric timeline validator for conflict detection and calibration marking

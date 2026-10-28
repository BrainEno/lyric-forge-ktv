# [2026-10-20 20:48] 插入服务尾部音频时长边界（E2.2）

- Scope: 阶段 E2 第二步。为 `LyricTimelineInsertionService.insertAtPlayback` 增加可选 `audioDuration` 参数；尾部插入时结束时间不超过音频总时长；播放位置已超出音频时结束时间限制到音频末尾（可能产生零时长，由 `LyricTimelineValidator` 标记需校准）；最小时长保护不会绕过音频边界。
- Files: 修改 `lib/features/lyrics/domain/services/lyric_timeline_insertion_service.dart`（`insertAtPlayback` 新增 `audioDuration`，尾部边界截断与最小时长保护互斥）；修改 `test/features/lyrics/domain/services/lyric_timeline_insertion_service_test.dart`（新增 4 例音频时长边界测试）；`docs/log/entries/2026-10-20-2048-e2-insertion-audio-boundary.md`、`docs/work_log.md`。
- Validation: `dart format` 2 个文件（1 变更）；`flutter analyze --no-pub` 2 个文件 → No issues found；`flutter test --no-pub test/features/lyrics/domain/services/lyric_timeline_insertion_service_test.dart` → 10/10 通过（原 6 + 新 4）。
- Notes: 当 start >= audioDuration 时 end 被限制为 audioDuration，会出现 end <= start，这是预期行为，由 validator 的 zeroOrNegativeDuration/needsCalibration 兜底，不静默裁剪。未提供 audioDuration 时行为与之前完全一致，不影响既有调用（编辑器 `_insertLineAtPlayback` 未传 audioDuration）。
- Commit: Add audio duration boundary to tail lyric line insertion

# [2026-10-21 01:35] 歌词对齐回归样本测试集（E3.4）

- Scope: 阶段 E3 最后一步。新增可重复运行的歌词对齐回归样本测试集，覆盖完全匹配、错别字（高相似度）、低置信度匹配、漏行、歧义匹配、多余识别行、中英混排、空行等场景；重点断言低置信度与歧义行在自动模式下不被错误采纳，漏行与多余识别行被准确标记，高相似度错别字不被漏报，以降低错误替换而非仅追求补出更多歌词。
- Files: 新增 `test/features/lyrics/domain/services/lyric_alignment_regression_test.dart`（10 例回归样本）；`docs/log/entries/2026-10-21-0135-e3-regression-sample-set.md`、`docs/work_log.md`。
- Validation: `dart format` 1 个文件；`dart analyze` → No issues found；`flutter test --no-pub test/features/lyrics/domain/services/lyric_alignment_regression_test.dart` → 10/10 通过；全量 `flutter test --no-pub test/features/lyrics/` → 141/141 通过。
- Notes: 该测试集作为域层回归保障，可在后续对齐算法调整时重复运行。阶段 E3 现已完整：E3.1 域层阈值与状态（lowConfidence/ambiguous）、E3.2 applier 不自动采纳低置信/歧义行、E3.3 审核界面替换 vs 插入漏行判断、E3.4 回归样本测试集。
- Commit: Add lyric alignment regression sample test set

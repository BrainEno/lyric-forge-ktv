# [2026-10-21 01:28] 审核界面支持歧义匹配的替换或插入漏行判断（E3.3）

- Scope: 阶段 E3 界面层部分。在逐行确认面板中，对低置信度和歧义匹配条目展示明确标识（“低相似”/“歧义匹配”徽标），并允许用户对歧义匹配判断是“替换此行”还是“将参考歌词作为漏行插入”，或跳过；不自动采纳低置信与歧义行，降低错误替换。
- Files: 修改 `lib/features/lyrics/presentation/widgets/reference_alignment_review.dart`（`_correctableEntries` 包含 replace/lowConfidence/ambiguous；ambiguous 条目显示“歧义匹配”徽标与三项互斥选择（替换/插入漏行/跳过），选择结果写入 `_ambiguousChoice` 并分别进入 `acceptedReferenceIndices` 或 `acceptedMissingReferenceIndices`）；修改 `lib/features/lyrics/domain/services/reference_alignment_applier.dart`（歧义条目若被选为“插入漏行”，按其匹配 ASR 行位置合成插入项，requiresConfirmation=true）；新增 `test/features/lyrics/presentation/widgets/reference_alignment_review_test.dart`（歧义匹配显示两种选择、选择替换、选择插入漏行 3 例）；`docs/log/entries/2026-10-21-0128-e3-review-ambiguous-choice.md`、`docs/work_log.md`。
- Validation: `dart format` 3 个文件；`flutter analyze --no-pub` 域层+界面层 3 个文件 → No issues found；`flutter test --no-pub test/features/lyrics/` → 131/131 通过。
- Notes: 审核面板对 lowConfidence 条目目前不强制额外二次确认（仅不自动采纳、显示低相似徽标），如需更严格可在后续加强。可重复运行的歌词样本测试集（E3.4）尚未作为独立文件，当前已通过 alignment/applier 单测覆盖错配、漏行识别与错误自动采纳防止；如需可追加专门样本测试文件。
- Commit: Allow ambiguous match replace vs insert-as-missing choice in review UI

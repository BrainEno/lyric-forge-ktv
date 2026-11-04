# Handoff

## 目标

本轮独立切片只迁移 ASR review-item 的 `ProofreadReason` 文案：domain assembler 将原因作为 typed enum codes 携带，presentation 的 `LyricReviewStrings` 映射原有中文标签并由 dialog 显示。Forced-alignment supplemental hints、reference-first reasons、Proofread V2 explanations 不在本切片范围内。

## Git 现场

- Repository：`BrainEno/lyric-forge-ktv`
- 活动分支：`arena/1157f521-lyric-forge-ktv`。
- 基线：PR #344 已合并，merge commit `7cfae19fbedb3fce2b0f48dd82b6fab7a4024c0a`。
- 实现提交：`c13355c refactor: move ASR review reasons to presentation`。
- PR #345：<https://github.com/BrainEno/lyric-forge-ktv/pull/345>，OPEN，供 review；未经用户授权不得合并。
- Issue #335 已 CLOSED；本切片不重开，也不作为 PR 的关闭目标。
- PR #345 最终 head 的 pinned Flutter Quality Gate 尚待通过；如有后续提交，只以最新 head 对应的 run 为准。

## 已改文件

- `lib/features/lyrics/domain/proofreading/proofread_review_proposal.dart`：为 review item 增加不可变的 `ProofreadReason` code 集合。
- `lib/features/lyrics/domain/proofreading/proofread_v2_review_assembler.dart`：ASR 路径传递 typed reasons，移除领域层 `ProofreadReason` 到中文文案映射；forced-alignment hints 保持原状。
- `lib/features/lyrics/presentation/lyric_review_strings.dart`：集中映射全部 16 种 `ProofreadReason` 到既有文案。
- `lib/features/lyrics/presentation/widgets/lyric_proofread_v2_dialog.dart`：在 presentation 边界组合 typed reason 文案与尚未迁移的 forced-alignment hints。
- assembler、string 与 dialog 测试覆盖 typed reason、全量文案映射和 UI 可见内容。
- `docs/log/entries/2026-11-05-0118-move-asr-review-reasons-to-presentation.md`、生成的 work-log 导航与本 handoff 记录该切片。

## 检查结果

- `git diff --check` 通过；临时 WASM `dart_style` 对所有 changed Dart files 的格式检查通过。
- 本地无 Flutter/Dart SDK，未运行 analyzer 或 Flutter tests。
- PR #345 最终 head 的 pinned Flutter Quality Gate 必须通过后，才可认为验证完成。

## 下一步

确认 PR #345 最终 head 的 Flutter Quality Gate 通过；PR 留给用户 review，不要代为合并。后续可再独立迁移 ForcedAligner supplemental reason hints，再评估 Proofread V2 explanations。Issue #335 保持关闭。

## 已知风险

- `ProofreadReason` code 集合保持 ASR pipeline 的结构化原因；新 enum 值会要求 presentation switch 增加文案，完整映射测试应继续覆盖所有值。
- 本地没有 Flutter/Dart SDK，验证依赖固定工具链 CI。
- native、KTV recovery、runtime-release、icon 和其他 specialist workflows 未审计或改动。

最后更新：2026-11-05（Asia/Hong_Kong）

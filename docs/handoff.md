# Handoff

## 目标
继续歌词智能校对 V2：不要把缺少置信度的 ForcedAligner 词级时间结果显示为模型置信度；保持时间证据仅供复核，不自动修改歌词时间戳。

## Git 现场
- 仓库：`BrainEno/lyric-forge-ktv`。
- 基线：PR #186 已合并，main merge commit `9933a36fdfea662423a404fa8f1ac5ff0f519f24`。
- 开发分支：`fix/unknown-forced-align-confidence-20261026`。
- PR #187：<https://github.com/BrainEno/lyric-forge-ktv/pull/187>；合并前必须核对该 PR 最新 head 的 Flutter Quality Gate。
- 本轮将 `TimedLyricToken.confidence` 改为可空；对齐端未提供校准置信度时使用 `null`，不再人为填入 60。
- 本执行环境没有本地 Dart/Flutter SDK；分析和测试需以 GitHub Actions 最新 head 的结果为准。

## 已改文件
- `lib/features/lyrics/domain/proofreading/proofread_result.dart`
- `lib/features/lyrics/domain/proofreading/asr_first_pipeline.dart`
- `lib/features/lyrics/presentation/widgets/lyric_proofread_v2_dialog.dart`
- `test/features/lyrics/domain/proofreading/asr_first_pipeline_test.dart`
- `test/features/lyrics/presentation/widgets/lyric_proofread_v2_dialog_test.dart`
- `docs/high_quality_asr.md`
- `docs/work_log.md`
- `docs/work_log_archive.md`
- `docs/log/entries/2026-10-26-1512-unknown-forced-align-confidence.md`

## 本轮实现
- 词级置信度现在允许 `null`，同时继续校验明确提供的置信度必须处于 0–100。
- ForcedAligner 对齐跨度没有置信分数字段，所以映射时保留为未知，而不是虚构 60。
- 复核 UI 对真实提供的置信值显示百分比；缺失时显示“置信度未提供”。
- 测试覆盖缺失值及现有显式置信值展示；歌词原文和行级时间继续保持不变。

## 检查结果
- 已通过 GitHub 文件 API 核实源代码、回归断言和 ASR 文档改动。
- 未执行本地 `dart format`、`flutter analyze` 或 `flutter test`，因为当前环境未提供 Dart/Flutter SDK。
- 合并前必须检查此分支最新提交对应的 Flutter Quality Gate。

## 下一步
在最新 head 的 Flutter Quality Gate 通过后，审阅并合并此 PR；再使用已重建的 Windows/RTX 5080 runtime 与真实中、英、日歌曲进行端到端验收。

## 已知风险
- 契约与 UI 测试不证明真实歌曲的 token 时间准确度。
- `/v1/align` 当前没有校准置信度；除非未来后端明确提供有文档定义的分数，否则 UI 不应合成一个。
- 旧 runtime bundle 可能尚未包含 `POST /v1/align` endpoint。

最后更新：2026-10-26 15:12（Asia/Taipei）

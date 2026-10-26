# Handoff

## 目标
完成 ForcedAligner 词级时间证据的有界匹配与可见诊断闭环：让用户看到行覆盖率、未分配片段和未匹配行号，尤其明确显示对齐成功但无可用证据的情况。所有词级时间仍只供人工复核。

## Git 现场
- 仓库：`BrainEno/lyric-forge-ktv`。
- 主线基线：PR #188 已合并，提交 `187fb49bacbb09083ca01ec796f061676bd82c39`。
- 当前分支：`feat/forced-align-recovery-diagnostics-20261026`；相关工作集中在 PR #189。
- 本轮将 PR #189 从领域匹配拓展为端到端诊断呈现，避免单独阶段之间出现已计算但未展示的诊断。
- 本执行环境没有本地 Dart/Flutter SDK；必须以更新后 PR head 的 GitHub Actions 为验证依据。

## 已改文件
- `lib/features/lyrics/domain/proofreading/proofread_result.dart`
- `lib/features/lyrics/domain/proofreading/asr_first_pipeline.dart`
- `lib/features/transcription/data/services/forced_alignment_proofread_service.dart`
- `lib/features/lyrics/presentation/screens/lyric_editor_screen.dart`
- `lib/features/lyrics/presentation/widgets/lyric_proofread_v2_dialog.dart`
- `test/features/lyrics/domain/proofreading/asr_first_pipeline_test.dart`
- `test/features/transcription/forced_alignment_proofread_service_test.dart`
- `test/features/lyrics/presentation/widgets/lyric_proofread_v2_dialog_test.dart`
- `docs/high_quality_asr.md`
- `docs/work_log.md`、`docs/work_log_archive.md`、`docs/work_log_index.md`
- `docs/handoff.md` 与本轮独立工作日志条目

## 本轮实现
- ForcedAligner 成功返回后始终将 `forcedAlignmentRequested` 设为 true；空 spans 现在产生明确的零覆盖率诊断。
- 服务 warning 会呈现匹配行数、百分比覆盖率、跳过片段数和一基未匹配行号；对完整且没有跳过片段的结果不制造警告。
- 复核对话框新增诊断摘要区，展示覆盖率、未分配片段、未匹配歌词行和“仅供人工复核”的边界说明。
- 编辑器只在实际存在词级 token 时才说明“已提供词级证据”，不会在运行成功但返回空证据时作出误导性陈述。
- 新增服务回归测试覆盖跳过片段、前一行缺失但后续行恢复、零 span 成功响应及源歌词/行级时间戳不变；新增 widget 测试确认诊断字段可见。

## 检查结果
- 已添加定向回归测试，但没有在本执行环境运行 `dart format`、`flutter analyze` 或 `flutter test`，因为没有本地 Dart/Flutter SDK。
- 更新后的 PR head 必须通过 Flutter Quality Gate；本轮不会将“已加入测试”表述成“测试通过”。
- 合成 spans 验证匹配规则、诊断呈现和不修改源文档的边界，不证明真实音频的声学时间精度。

## 下一步
1. 检查更新后 PR #189 的 Flutter Quality Gate，并按真实失败日志修复。
2. 通过并合并后，在已重建且含 `POST /v1/align` 的 runtime 上选取真实中文、英文、日文歌曲，记录每行覆盖率、错误匹配和词级时间偏差。
3. 真实音频验收后，再独立设计“显式确认后修复行级时间戳”的流程；不能直接批量应用 token 时间。

## 已知风险
- 向前恢复窗口最多跳过 12 个 span，每行最多聚合 128 个 span；超界时保守报告未匹配。
- 跳过的片段可能是伴唱，也可能属于未匹配的歌词，界面只称“未分配”，不代替用户判断。
- 当前 endpoint 没有校准置信分数；ForcedAligner token 的 confidence 仍为 null。
- 真实中文/英文/日文歌曲的时间精度尚未验证，已下载的旧 runtime bundle 也可能没有 `POST /v1/align`。

最后更新：2026-10-26 16:20（Asia/Taipei）

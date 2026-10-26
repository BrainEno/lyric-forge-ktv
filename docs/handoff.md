# Handoff

## 目标
第一阶段改善 ForcedAligner 词级时间证据到歌词行的匹配：在有限范围内恢复额外片段造成的错位，记录结构化覆盖诊断，并保持源歌词与行级时间戳不变。

## Git 现场
- 仓库：`BrainEno/lyric-forge-ktv`。
- main 基线：PR #188 已合并，合并提交 `187fb49bacbb09083ca01ec796f061676bd82c39`。
- 开发分支：`feat/forced-align-recovery-diagnostics-20261026`。
- 本阶段只修改领域模型、ASR-first pipeline 和其领域回归测试；服务 warning 与 UI 显示留待下一阶段，确保阶段边界清晰。
- PR #189：<https://github.com/BrainEno/lyric-forge-ktv/pull/189>，尚未合并。
- 本执行环境没有本地 Dart/Flutter SDK；分析、格式化和测试需以此分支最新 head 的 GitHub Actions 为准。

## 已改文件
- `lib/features/lyrics/domain/proofreading/proofread_result.dart`
- `lib/features/lyrics/domain/proofreading/asr_first_pipeline.dart`
- `test/features/lyrics/domain/proofreading/asr_first_pipeline_test.dart`
- `docs/high_quality_asr.md`
- this handoff

## 本阶段实现
- 新增不可变 `ProofreadAlignmentDiagnostics`，包含总行数、匹配行数、覆盖率、跳过 span 数、零基未匹配行索引与一基行号转换。
- 匹配器最多向前搜索 12 个额外 span 的候选起点，每个候选最多聚合 128 个 span。
- 匹配保持 source order，成功消费的 span 不复用；某行无法匹配时保留最后确认边界，允许后续歌词行在有界范围内恢复匹配。
- 新增回归测试覆盖额外 span、前行缺失但后行可恢复、超出搜索预算、重复副歌按序消费、成功但空 spans、诊断覆盖率与不变量、以及源歌词不变。

## 检查结果
- GitHub Actions run 40289442193 在实现 head `2f32facdde5c94832ef8808382985c8c6862176a` 通过：work-log lint 0 errors/0 warnings、704 tests passed、repository quality gate passed。
- 本执行环境没有 Dart/Flutter SDK，未运行本地命令。新增的工作日志同步会产生新的 PR head，合并前仍要核对该最新 head 的 CI。
- 合成 span 验证文本匹配与安全边界，不代表真实歌曲的声学时间精度。

## 下一步
1. 先让本阶段领域改动通过 CI，并提交 PR。
2. 合并后再将结构化诊断接入 `ForcedAlignmentProofreadService` 的 warning 和复核说明 UI，增加服务/widget 回归测试。
3. 随后用含 `POST /v1/align` 的新版 runtime，在真实中文、英文、日文音频上验收覆盖率与时间边界。

## 已知风险
- 12-span look-ahead 与 128-span line cap 是有意的计算上限；超出范围时仍会报告为未匹配，不会扩大到无界搜索。
- 被跳过的 span 可能来自 ad-lib，也可能属于某条未匹配歌词，所以域层只称为“跳过片段”，不擅自判断为噪声。
- `/v1/align` 结果仍为复核证据；没有真实歌曲验收之前不得自动应用词级时间戳。

最后更新：2026-10-26 16:15（Asia/Taipei）

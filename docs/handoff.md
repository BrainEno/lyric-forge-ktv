# Handoff

## 目标
改善 ForcedAligner 词级时间证据到歌词行的匹配：在有限范围内恢复额外片段造成的错位，并把覆盖率、跳过片段和未匹配行暴露给人工复核。不得自动修改源歌词或行级时间戳。

## Git 现场
- 仓库：`BrainEno/lyric-forge-ktv`。
- main 基线：PR #188 已合并，合并提交 `187fb49bacbb09083ca01ec796f061676bd82c39`。
- 开发分支：`feat/forced-align-recovery-diagnostics-20261026`。
- 当前改动新增结构化 `ProofreadAlignmentDiagnostics`；逐行匹配最多向前略过 12 个 span、每个候选最多聚合 128 个 span。匹配严格遵循 source order，已消费 span 不会被复用。
- 本执行环境没有本地 Dart/Flutter SDK；分析、格式化和测试需以此分支最新 head 的 GitHub Actions 为准。

## 已改文件
- `lib/features/lyrics/domain/proofreading/proofread_result.dart`
- `lib/features/lyrics/domain/proofreading/asr_first_pipeline.dart`
- `lib/features/transcription/data/services/forced_alignment_proofread_service.dart`
- `lib/features/lyrics/presentation/screens/lyric_editor_screen.dart`
- `test/features/lyrics/domain/proofreading/asr_first_pipeline_test.dart`
- `test/features/lyrics/domain/proofreading/proofread_result_test.dart`
- `test/features/transcription/forced_alignment_proofread_service_test.dart`
- `docs/high_quality_asr.md`
- `docs/work_log_index.md`
- `docs/work_log.md`
- `docs/work_log_archive.md`
- this handoff and a new immutable work-log entry

## 本轮实现
- 添加不可变 `ProofreadAlignmentDiagnostics`，记录总行数、匹配行数、覆盖率、跳过的 span、未匹配行索引和供 UI 使用的一基行号。
- 对齐服务成功但返回空 span 时记录零覆盖率；这与运行时不可用的 fallback 区分开。
- 匹配器可在当前 cursor 后最多搜索 12 个 span 的候选起点；每个起点最多拼接 128 个 span，保持最早命中、按序消费、不重复使用证据的原则。
- 一行未匹配时保留最后确认的 cursor，允许后续歌词行独立恢复；将未匹配行和跳过的片段报告给复核流程，不把它们静默当成成功。
- 复核说明展示词级覆盖率、匹配行数、跳过片段及未匹配行号。
- 新增测试覆盖 ad-lib/额外 span 恢复、早期行未匹配时后续行仍可匹配、搜索上限、重复副歌顺序、空对齐结果、诊断对象的范围校验及不可变性。

## 检查结果
- 已写入领域/服务/UI 回归测试，并更新 ASR 技术说明。
- 尚未在本执行环境运行 Dart/Flutter 命令；需以最新 head 的 Flutter Quality Gate 判断是否通过。
- 合成 span 测试只验证匹配逻辑与安全边界，不代表实际声学时间精度。

## 下一步
等待最新 head 的 CI；若失败，根据真实日志修复。通过后提交 PR 给用户审阅。合并后仍需用已重建且包含 `POST /v1/align` 的 Windows/RTX 5080 runtime 进行真实中文、英文、日文音频验收。

## 已知风险
- 12-span look-ahead 与 128-span line cap 有意限制计算规模；超出范围的对齐仍会作为未匹配证据提示人工处理。
- 跳过的 span 可能是 ad-lib，也可能属于未匹配歌词行，因此用“跳过片段”而不直接断言为噪声。
- 真实歌曲中的时间精度、覆盖率和 runtime bundle 接口可用性尚未实际验证；不应据合成测试开启自动时间戳应用。

最后更新：2026-10-26 16:05（Asia/Taipei）

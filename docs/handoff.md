# Handoff

## 目标
提高最高质量 ASR 的真实可测性：确保同一音频的 Whisper、Qwen 与融合结果能追溯到明确输入，并且参考歌词已经人工复核。

## Git 现场
- 仓库：`BrainEno/lyric-forge-ktv`
- 当前分支：`feat/asr-eval-provenance-20261027`
- 基线：main 已包含 PR #198 的配对文本评测与插入/删除/替换分项；main commit 为 `b5cebb6845bcb3d9e025744ea1bf6ca4838f59b7`。
- 当前执行环境没有本地 Git/Flutter 工作树；以 GitHub Actions 运行格式、分析、测试和 work-log contract preflight。

## 已改文件
- `tool/asr_transcript_eval.dart`
- `test/tool/asr_transcript_eval_test.dart`
- `docs/high_quality_asr.md`
- `docs/log/entries/2026-10-27-1546-track-asr-evaluation-provenance.md`
- `docs/work_log.md`
- `docs/work_log_archive.md`
- `docs/work_log_index.md`
- `docs/handoff.md`

## 本轮实现
- 语料样本可记录 exact-input `audioSha256`、`audioDurationMs` 以及 `referenceReviewed`。
- 每个 engine candidate 可分别记录 `audioSha256`、`modelRevision` 和 `runtimeVersion`；如候选指纹存在，必须与样本指纹相同，否则拒绝评测。
- 评测报告新增 `provenance` 覆盖率、缺失字段清单与 warnings。
- schemaVersion 1 的旧语料仍可评测；缺失来源元数据会告警，不会伪装成可完全复现的比较。
- 文档说明通过 PowerShell 对实际送入识别器的音频计算 SHA-256。

## 检查结果
- 新增完整 provenance、旧语料告警、音频指纹不匹配和非法元数据测试。
- 当前 PR head 的格式、分析、测试和 work-log 检查等待 GitHub Actions 确认。
- 没有真实人工标注歌曲语料，尚不能评估模型优劣或声称准确率提升。

## 下一步
CI 通过后，合并本 PR；然后用人工核验的英文、中文、日文样本填充本地评测语料。先确认每个样本与所有候选的 SHA-256、时长、模型版本和人工复核状态，再运行 transcript 与 ForcedAligner 评测器，按文本错误和时间误差分开分析。

## 已知风险
- SHA-256 只能确认字节输入相同，不能证明识别器输出对应这个文件，也不能证明 reference 正确。
- `referenceReviewed: true` 是人工声明，不是工具自动听音验证。
- 旧语料可继续运行，但只有 provenance 字段完整时，比较才具备可审计的来源记录。

最后更新：2026-10-27 15:46（Asia/Taipei）

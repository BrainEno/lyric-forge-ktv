# Handoff

## 目标
让 ASR 评测在需要严谨模型比较时可以 fail closed：缺少可追溯输入、人工参考复核或模型/运行时标识，就拒绝将报告作为完整基准通过，但依然保存诊断报告。

## Git 现场
- 仓库：`BrainEno/lyric-forge-ktv`
- 当前分支：`feat/asr-eval-strict-provenance-20261027`
- 基线：main 包含 PR #198 与 PR #199；基线 commit 为 `26116b164d6273de412842347c761c864a4c44c5`。
- 当前执行环境没有本地 Git/Flutter 工作树；通过 GitHub Actions 做格式、分析、完整测试及 work-log contract preflight。

## 已改文件
- `tool/asr_transcript_eval.dart`
- `test/tool/asr_transcript_eval_test.dart`
- `docs/high_quality_asr.md`
- `docs/log/entries/2026-10-27-1610-require-strict-asr-provenance.md`
- `docs/work_log.md`
- `docs/work_log_archive.md`
- `docs/work_log_index.md`
- `docs/handoff.md`

## 本轮实现
- 新增 CLI 参数 `--require-provenance)，可与 `--output` 按任意顺序组合。
- 严格模式要求样本声明音频 SHA-256、正数时长和 `referenceReviewed: true`；候选声明匹配的 SHA-256、模型修订与运行时版本。
- 发现缺项时先写出包含 provenance 缺失清单的报告，再以退出码 2 失败，方便自动化流程停下且保留诊断。
- 默认模式仍兼容旧语料并报告 warnings。
- 回归测试覆盖完整 provenance 成功和旧语料严格模式失败。

## 检查结果
- 最新代码 head `94b3e753f793ed4caed7356fd10c3772d6056045` 的 Flutter Quality Gate run `40477102575` 已通过；work-log contract preflight、Dart 格式检查通过，完整测试为 737 项全部通过。之后仅更新了任务验证记录，相关文档 head 的 CI 仍需确认。

## 下一步
CI 通过后合并 PR；再使用本地英文、中文、日文音频建立人工复核语料，先运行严格文本评测并对同一音频运行 ForcedAligner 评测，基于真实分项统计决定是否调整融合策略。

## 已知风险
- 严格 provenance 只检查用户声明的元数据是否完整，不会自动证明参考歌词正确，也不自动 hash 被引擎实际读取的音频文件。
- `referenceReviewed: true` 是人工复核声明，不是机器验证结论。
- 有意保持严格模式 opt-in，避免旧语料突然无法继续计算历史指标。

最后更新：2026-10-27 16:20（Asia/Taipei）

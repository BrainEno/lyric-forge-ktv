# Handoff

## 目标
让 ForcedAligner 的时间精度评测与文本 ASR 评测一样可追溯：同一真实音频、人工复核的时间参考、明确的模型修订与运行时版本；缺少关键来源元数据时可严格失败，但保留诊断报告。

## Git 现场
- 仓库：`BrainEno/lyric-forge-ktv`
- 当前分支：`feat/strict-forced-alignment-provenance-20261027`
- 基线：main commit `4c9a0e703f1821a0e1d3c66ec3c2b81a6168173b`；PR #200 已合并，合并后的 main 质量门通过。
- 当前执行环境没有本地 Git/Flutter 工作树；使用 GitHub Actions 运行格式、分析、完整测试及 work-log contract preflight。

## 已改文件
- `tool/forced_alignment_eval.dart`
- `test/tool/forced_alignment_eval_test.dart`
- `docs/high_quality_asr.md`
- `docs/log/entries/2026-10-27-1707-strict-forced-alignment-provenance.md`
- `docs/work_log.md`
- `docs/work_log_index.md`
- `docs/handoff.md`

## 本轮实现
- ForcedAligner 评测报告新增 provenance 覆盖率、缺失样本清单与 warnings；默认模式仍兼容旧语料。
- capture 在本地 `/v1/align` 请求前计算音频 SHA-256，结束后再次计算；文件在识别过程中变化就拒绝保存语料。
- capture 可显式记录 `referenceReviewed`、`modelRevision` 与 `runtimeVersion`；只有传入 `--reference-reviewed` 才记录人工复核为 true。
- 评测 CLI 支持 `--require-provenance` 和 `--output` 任意顺序组合；来源不完整时先保存报告，再以退出码 2 失败。

## 检查结果
- PR #201 implementation head `0ec5ccd994953561b9ba6ac92039bef952a711ed` 的 Flutter Quality Gate run 40480645675 全部通过：work-log preflight、Dart format、repository quality gate；全量测试 `741 tests passed`。
- 本次仅更新验证记录/交接文档，产生新 PR head 后仍需确认最新 head 的 CI 结论。

## 下一步
CI 通过并合并后，使用本人本地人工复核的英文、中文、日文音频分别记录 transcript 与 ForcedAligner 结果；在真实数据到位前不调整或宣称融合准确率提升。

## 已知风险
- SHA-256 可识别音频字节变化，但旧手工语料里的指纹仍是声明值，不能证明过去运行时实际加载了该文件。
- `referenceReviewed` 仍是人工声明，模型/runtime 字符串也需要填写真实 revision 与 bundle 版本。
- 合成测试只验证契约与边界，不证明真实歌曲的时间精度或中英日覆盖。

最后更新：2026-10-27 17:28（Asia/Taipei）

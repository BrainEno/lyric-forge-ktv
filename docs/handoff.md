# Handoff

## 目标
把同音频多引擎识别质量评测做成可解释的诊断：不仅量化错误率，还要区分多余文本、漏识别文本和字符/词替换，以便后续有证据地评估融合策略。

## Git 现场
- 仓库：`BrainEno/lyric-forge-ktv`
- 当前分支：`feat/asr-transcript-evaluator-20261027`
- 目标 PR：https://github.com/BrainEno/lyric-forge-ktv/pull/198
- 基线：main 包含 PR #197 的双模型独有歌词保留与时间感知子串匹配修复。
- 当前执行环境没有本地 Git/Flutter 工作树；以 GitHub Actions 进行格式、分析与测试验证。

## 已改文件
- `tool/asr_transcript_eval.dart`
- `test/tool/asr_transcript_eval_test.dart`
- `docs/high_quality_asr.md`
- `docs/log/entries/2026-10-27-1206-report-asr-edit-breakdown.md`
- `docs/work_log.md`
- `docs/work_log_archive.md`
- `docs/work_log_index.md`
- `docs/handoff.md`

## 本轮实现
- 使用紧凑的方向矩阵与滚动成本行回溯最小编辑路径，避免为了统计错误类别再分配完整整数 DP 矩阵。
- 字符、token 维度报告 insertions、deletions、substitutions；每层分项之和等于 edit count。
- 对每个样本及按引擎/语言聚合的结果输出分项计数；英文可比较样本额外提供 word 级分项。
- 文档说明：插入表示候选文本多出的单位，删除表示参考文本中未识别出的单位，替换表示文本错误；这些是排查线索，不是语义级自动判定。

## 检查结果
- 新增分项统计回归测试。
- 本分支的新 CI 尚未运行/确认；以 PR #198 最新 head 的 Flutter Quality Gate 和 work-log lint 为准。
- 未运行真实歌曲评测，无准确率提升声明；必须先用人工听音核验的参考歌词。

## 下一步
CI 通过后，等待 PR #198 合并，再建立英文、中文、日文同音频语料，并同时跑 transcript evaluator 与 ForcedAligner evaluator；按漏识别、冗余文本、替换错误、时间边界误差分别分析，再考虑调节融合门槛。

## 已知风险
- 最小编辑脚本在平局时采用固定优先级，因此某一编辑类别分项可能与另一个同成本路径不同；编辑总数和 CER 不受影响。
- 插入/删除/替换不能直接判断“幻觉”或“正确漏词”，因为人工 reference 本身可能漏记伴唱/即兴词；仍需听音复核。
- 编辑方向矩阵限制在既有 DP cell 上限内，超限样本应切分为短片段。

最后更新：2026-10-27 12:06（Asia/Taipei）

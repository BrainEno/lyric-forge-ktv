# Handoff

## 目标
为 ForcedAligner 的真实音频验收建立可重复、可量化的评估工具；对人工校验的参考时间与实际运行输出计算多语言文本覆盖及时间边界误差，不修改歌词或对齐时间。

## Git 现场
- 仓库：`BrainEno/lyric-forge-ktv`。
- 基线：PR #189 已合并，merge commit `040b9b4fbd09ddb180a31163902e289508477227`。
- 当前分支：`feat/forced-alignment-quality-evaluator-20261026`。
- 当前任务只添加离线评估工具、合同测试与运行说明，不改生产运行时和用户界面。
- 本执行环境没有本地 Dart/Flutter SDK；必须以本分支最新 GitHub Actions 结果为验证依据。

## 已改文件
- `tool/forced_alignment_eval.dart`
- `test/tool/forced_alignment_eval_test.dart`
- `docs/high_quality_asr.md`
- `docs/work_log.md`、`docs/work_log_archive.md`、`docs/work_log_index.md`
- 本文件与独立工作日志条目

## 本轮实现
- 读取包含人工标注 reference spans 和实际 ForcedAligner 输出的 JSON corpus。
- 使用有界、按顺序的文本匹配，允许每侧最多 8 个连续 span 组成一个匹配组，减少分词粒度不同带来的无谓漏配。
- 报告文本 precision/recall、未匹配 span、起止时间边界 MAE/median/P95/max，以及容差内边界比率；支持总体和逐语言汇总。
- 校验时间顺序、音频边界、唯一样本 ID、输入 schema 及动态规划内存预算。
- 工具不推断缺失时间、不修复结果、不把合成测试当作真实音频准确率。

## 检查结果
- 新增定向测试覆盖基础时间误差、全角拉丁/中日文、额外片段、空输出、按语言汇总及输入校验。
- 尚未本地运行 Dart format/analyze/test；没有本地 Dart/Flutter 工具链。
- PR 的 Flutter Quality Gate 必须验证格式、分析、测试和 work-log lint；真实音频还需在重建后的本机 runtime 上采集。

## 下一步
1. 根据最新 CI 失败日志修正工具/测试。
2. 在 Windows/RTX 5080 上对人工标注的中文、英文、日文样本执行评估，检查 coverage 与 P95 boundary error。
3. 依据真实数据决定是否推进显式确认后的行级时间修复；不可直接自动应用词级时间。

## 已知风险
- 没有随仓库提供任何真实音频或 gold 时间标注，输出质量取决于输入参考的准确性。
- 有序分组窗口最多 8 个 span，单样本动态规划矩阵限制为 1,000,000 个单元；过长样本应拆成可人工复核的小段。
- 当前 ForcedAligner 不提供校准置信分数，本工具不评估或伪造置信度。

最后更新：2026-10-26 16:35（Asia/Taipei）

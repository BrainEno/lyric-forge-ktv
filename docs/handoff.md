# Handoff

## 目标
继续提高最高质量 ASR 的可量化识别效果：提供同一段音频上 Whisper、Qwen 和融合结果的配对文字评测，不把运行链路成功误当作歌词准确。

## Git 现场
- 仓库：`BrainEno/lyric-forge-ktv`
- 当前分支：`feat/asr-transcript-evaluator-20261027`
- 基线：main 包含 PR #197 的双模型独有歌词保留与时间感知子串匹配修复。
- 当前执行环境没有本地 Git/Flutter 工作树；以 GitHub Actions 进行验证。

## 已改文件
- `tool/asr_transcript_eval.dart`
- `test/tool/asr_transcript_eval_test.dart`
- `docs/high_quality_asr.md`
- `docs/log/entries/2026-10-27-0250-add-asr-transcript-evaluator.md`
- `docs/work_log.md`
- `docs/work_log_index.md`
- `docs/handoff.md`

## 本轮实现
- 每个样本共享一份人工核验 referenceText，并可在同一样本里列出多个 engine 的候选输出。
- 输出按 engine 和 language 汇总的归一化 CER、token error rate 与适用时的 WER；聚合按总编辑数/参考单位数加权，不平均各歌曲比率。
- 中日韩和混合文本中，遇到 CJK 时 WER 显示 null，不伪装成常规分词的 WER。
- 空识别结果作为完整漏识别计分；校验重复样本 ID、重复引擎名、无有效歌词字符的 reference 和评测复杂度上限。
- 继续使用既有 ForcedAligner evaluator 评估 span 召回与边界误差，两套指标职责分离。

## 检查结果
- 新增评测工具及测试的最终格式、分析和测试状态待 GitHub Actions 确认。
- 当前没有真实人工标注的多语种歌曲语料，因此只能声称评测工具可用性，不能声称模型识别准确率已提高。

## 下一步
CI 通过后，先为一首英文歌、一首中文歌和一首日文歌建立同音频、人工核验的参考文本；将 Whisper、Qwen 和融合输出放进同一个样本，比较 CER 和适用时的 WER。另用人工核验的行级时间区间跑 ForcedAligner evaluator，衡量歌词漏行、冗余行和时间误差，再基于证据调整融合策略。

## 已知风险
- CER 忽略标点、空白与大小写，适合歌词文字比较但不衡量标点样式。
- WER 不对 CJK 或混合 CJK 候选输出计算；这些样本应看 CER/token error rate。
- reference 不完整、漏掉实际演唱的伴唱/即兴词，会系统性地惩罚正确输出；每个参考文本必须人工听音核验。

最后更新：2026-10-27 02:50（Asia/Taipei）

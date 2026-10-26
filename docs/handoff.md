# Handoff

## 目标
提高最高质量 ASR 的歌词召回率，避免副识别器找到的独立歌词/伴唱词因时间区间落在主识别器的长行内部而被误当成“已匹配”丢弃。

## Git 现场
- 仓库：`BrainEno/lyric-forge-ktv`
- 当前分支：`feat/asr-quality-metrics-and-recall-20261027`
- 基线：main 已包含 PR #195 的双模型融合修复与 PR #196 的 V2 试听修复。
- 当前执行环境没有本地 Git/Flutter 工作树；远端 GitHub Actions 负责格式、分析器和测试验证。

## 已改文件
- `lib/features/transcription/data/services/high_quality_transcription_service.dart`
- `test/high_quality_transcription_service_test.dart`
- `docs/high_quality_asr.md`
- `docs/log/entries/2026-10-27-0018-preserve-overlapping-asr-lines.md`
- `docs/work_log.md`
- `docs/work_log_archive.md`
- `docs/work_log_index.md`
- `docs/handoff.md`

## 本轮实现
- 双向合并不再把时间重叠的所有副识别行一概标为已匹配。
- 子串匹配还需与歌词片段预期位置或对应段落边界对齐；非子串的文本相似匹配还需时间重叠强且时长可比，起止边界近似的候选行也保留为同一行比较。
- 新颖的重叠副识别行保留为低置信度（最高 60）的单独复核行。
- 新增测试覆盖 Qwen-primary 与 Whisper-primary 两种配置中的“长主行 + 首尾对应片段 + 内部独立歌词/ad-lib”，包括文本虽为主行子串但时间位置不符的独立短句。

## 检查结果
- ASR client checks 已通过前一个代码 head；最新代码 head 的 Flutter Quality Gate 与完整回归套件尚待最终确认。
- 这是一项保守的召回保护，不代表模型本身 WER 已下降。真实音频仍需人工核验后计入评测语料。

## 下一步
CI 通过后，把真实歌曲的人工核验转录加入 ASR 评测语料，按语言、歌曲和引擎顺序分别统计字符/词错误率、漏行率、冗余行率和时间边界误差。不要仅凭模型置信度或成功运行 smoke test 判断准确性。之后再用相同输入音频比较 Whisper、Qwen 与融合结果，决定是否调整主模型或融合门槛。

## 已知风险
- 文本归一化子串和时间边界是候选匹配的启发式依据，无法替代人工金标准；某些 ad-lib 可能仍被判断为同一行，某些拆句可能出现多余待复核行。
- 所有新插入副识别行仍须人工确认，不能自动视为真实歌词。
- 没有实机音频语料评测前，不宣称整体准确率提升幅度。

最后更新：2026-10-27 00:48（Asia/Taipei）

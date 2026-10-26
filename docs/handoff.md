# Handoff

## 目标
修复 lyric-forge-ktv 的真实歌曲识别质量风险：双 ASR 漏行、Qwen 伪高置信度、Windows 高质量配置的主次模型选择，以及结果合并后的行索引一致性。

## Git 现场
- 仓库：`BrainEno/lyric-forge-ktv`
- 审查基线：`main@a6b4ae596bf966b5dcd9a99c4f07d6464cc9e705`
- 当前分支：`fix/asr-fusion-recall-confidence-20261026`
- PR #195： https://github.com/BrainEno/lyric-forge-ktv/pull/195
- 该执行环境没有本地 Git/Flutter 工作树；使用 GitHub 远端文件、比较结果和 Actions 验证。

## 已改文件
- `lib/features/transcription/data/services/high_quality_transcription_service.dart`
- `lib/features/transcription/data/services/native_transcription_profile_resolver.dart`
- `lib/features/transcription/data/services/qwen3_asr_native_transcription_service.dart`
- `test/high_quality_transcription_service_test.dart`
- `test/transcription_hardware_profile_test.dart`
- `docs/high_quality_asr.md`
- `docs/local_transcription.md`
- `docs/log/entries/2026-10-26-2035-improve-asr-fusion-recall.md`
- `docs/work_log.md`
- `docs/handoff.md`

## 本轮实现
- Windows RTX 5080 的最高质量 profile 暂时使用 Whisper large-v3 主识别、Qwen3-ASR 1.7B CUDA/BF16 第二意见。该默认是针对当前真实歌曲测试失败的可回退措施，不代表 Whisper 总体优于 Qwen。
- 双向对比完整时间戳转写结果；未与主识别任意一行重叠的副模型歌词不再静默丢弃，而是按时间排序插入、置信度最高 60，并进入人工复核。
- 插入歌词后重映射每行双模型备选项的索引，避免候选串到错误行。
- Qwen 未提供可校准歌词置信度时，使用 50 的待复核中性基线，不再用时间戳/文本结构推导出 92。
- Whisper-first 进度/元数据显示实际 Qwen 模型版本，不再硬编码 0.6B CPU。
- 新增两种主模型顺序下的副模型独有歌词回归测试，以及 Windows profile engine order 断言。

## 检查结果
- 比较结果：分支相对 main 前进 11 个提交，未落后；变更涉及 9 个文件（本 handoff 更新后为 10 个）。
- 新增 Flutter 测试尚未在本地执行：本环境无 Dart/Flutter SDK。必须以 PR #195 最新 head 的 Quality Gate 为准。
- 真实 Windows RTX 5080 上的 Roadhouse Blues 重测尚未执行；需要合并/检出分支、重建应用后，用同一音频对比输出行数与遗漏情况。
- 本改动没有声称真实歌曲识别精度已经得到声学验证。

## 下一步
先检查 PR #195 最新 head 的 work-log lint、Dart format、analyzer、定向测试和完整 Flutter Quality Gate；若 CI 有失败，先定位并修复。CI 通过后在 Windows RTX 5080 重建并复测 The Doors - Roadhouse Blues。此后单独继续排查 V2 单行试听的真实播放链路，并评估本地人声分离，因为当前转写仍可能直接使用带伴奏的混音。

## 已知风险
- 副模型独有的线索可能是误识别或 ad-lib；它们被限制为低置信度复核项，不自动视为真歌词。
- 两模型的区间/断句不同会让“完全不重叠”检测漏掉位于主模型宽区间内部的缺词；需要真实歌曲输出进一步评估。
- Qwen 的 50 是 UI 复核优先级分数，不是识别概率；ASR confidence 字段尚未统一成可校准、可空的类型。
- 当前源分离后端仍未完成；原始混音可能显著影响音乐人声识别。

最后更新：2026-10-26 20:40（Asia/Taipei）

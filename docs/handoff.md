# Handoff

## 目标

避免校对时次引擎分段的低置信度被平均分掩盖，保留人工复核。

## Git 现场

基线 `7910e3beed8ceb9346f417a789f2a926d1dcf8c3`，分支 `arena/67b864b7-lyric-forge-ktv`。验证后、写入本交接前快照：

```
 M docs/reviews/2026-11-07-asr-and-proofreading-review.md
 M docs/work_log_index.md
 M lib/features/lyrics/domain/proofreading/asr_first_pipeline.dart
 M test/features/lyrics/domain/proofreading/asr_consensus_analyzer_test.dart
 M test/features/lyrics/domain/proofreading/asr_first_pipeline_test.dart
 docs/reviews/2026-11-07-asr-and-proofreading-review.md | 1 +
 docs/work_log_index.md | 2 +-
 lib/features/lyrics/domain/proofreading/asr_first_pipeline.dart | 6 +-
 test/features/lyrics/domain/proofreading/asr_consensus_analyzer_test.dart | 81 +++++++++++++---------
 test/features/lyrics/domain/proofreading/asr_first_pipeline_test.dart | 26 +++++--
 5 files changed, 74 insertions(+), 42 deletions(-)
970330a Protect low confidence split ASR evidence
7910e3b Merge pull request #393 from BrainEno/arena/1806f5be-lyric-forge-ktv
```

暂存区为空。最终 PR 不保留临时验证 workflow；以当前 Git 状态为准。

## 已改文件

ASR 共识分析器、ASR-first pipeline、对应测试、审查报告和工作日志导航。

## 检查结果

固定 SDK Actions run 42626819397 在依赖解析后格式化，校对目录定向测试和完整静态分析通过。本地无 Flutter/Dart；无真实歌曲或手动 UI/设备验证。最终 PR 检查以 GitHub 状态为准。

## 下一步

用授权、人工核对的歌曲语料评估识别质量及相邻行混入；另行评估重复建议仍使用汇总平均分的风险。

## 已知风险

相邻无关片段的低分可能造成保守复核；重复建议独立使用平均分，未在本阶段改变。未评分不等于高置信。合成回归不能证明真实歌曲准确率；工程跨进程和其他无条件写入仍有风险。

最后更新：2026-11-07（Asia/Taipei）

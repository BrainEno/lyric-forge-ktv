# Handoff

## 目标

修复双引擎歌词互检漏报边界差异的问题。当前 Qwen/Whisper 的候选发现阈值为 0.72，"Ashin lady" / "passion lady" 的归一化字符相似度约为 0.727，差异候选可能被直接过滤掉。此阶段仅修复候选发现及回归测试，不改自动替换决策。

## Git 现场

- 当前执行环境只提供 GitHub API，没有本地 checkout；无法提供真实的本地 git status --short、git diff --stat 或 git log --oneline -5 输出。
- 审查基线 main：0474fdff3dbd985b6c0db9aeabb2ccf0941a01d5。
- 工作分支：fix/surface-weak-lyric-matches-core-20261022。
- 分支最新实现提交：67d3b08d769295ce99ddfa7b080b4420b80b4dc2；之前先提交了回归测试 2296eaaf353ed07e541bda8d16d234b41f4114b3。
- 尚未创建本阶段 PR；GitHub 未提供本地执行结果，且没有在此环境跑测试。

## 已改文件

- test/high_quality_transcription_service_test.dart：新增 Qwen 主引擎与 Whisper 主引擎两种顺序下的 "Ashin lady" / "passion lady" 回归测试，要求产生待复核候选，但不得因候选阈值而自动替换。
- lib/features/transcription/data/services/high_quality_transcription_service.dart：集中定义复核阈值 0.80，并同步更新两种引擎顺序的候选发现与原因码判定。
- docs/handoff.md：更新交接状态。
- docs/work_log_index.md：更新当前焦点。

## 检查结果

- 静态核对确认旧的四处 0.72 比较均改为共享的 0.80 复核阈值。
- 未运行 dart format、flutter test、flutter analyze 或质量门：当前无本地 checkout / Dart / Flutter 工具链。
- 未创建不可变 work-log 条目，也未手工修改生成文件 docs/work_log.md；需在本地验证后再记录完成任务。

## 下一步（唯一）

本地检出该分支，运行 dart format lib/features/transcription/data/services/high_quality_transcription_service.dart test/high_quality_transcription_service_test.dart、flutter test test/high_quality_transcription_service_test.dart、flutter analyze --no-pub 与相关回归。通过后再写任务日志、运行 dart tool/work_log.dart write/check 并标记 PR Ready。

## 已知风险

- 0.80 是“进入人工复核候选”的阈值，不是自动替换阈值；自动采用逻辑保持原样。候选数可能增加，这是以更多人工可见差异换取少漏报的刻意取舍。
- 字符相似度不懂语义；此改动只增加可复核证据，不代表备选一定正确。
- 下一阶段的候选卡字符级 diff 与行内试听/单句人声起止校准分开实施，避免把识别策略、播放控制和时间编辑一次性混入同一 PR。

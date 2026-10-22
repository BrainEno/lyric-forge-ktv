# Handoff

## 目标

推进歌词校对 V2 的 T2a：实现有界纯 Dart token 序列对齐、软匹配和 referenceCoverage。为遵守单任务约 300 行限制，唯一锚点链和重复副歌消歧拆为后续 T2b。

## Git 现场

- 本执行环境只有 GitHub 连接，没有本地 checkout；不能诚实提供本地 git status --short、git diff --stat 或 git log --oneline -5 输出。
- 已核实 GitHub main HEAD：61eb74d388d491ef6a39816f74224f05ec725f2a。
- 工作分支：feat/lyric-proofreading-t2-token-alignment-20261022；测试先行提交 b601ddd，T2a 实现检查点 4025b0e，本次 handoff/计划更新随后提交。
- GitHub 未返回该分支提交的 status checks 或 Actions workflow runs。

## 已改文件

- lib/features/lyrics/domain/proofreading/reference_token_aligner.dart：有界 Needleman–Wunsch token 对齐、token 软匹配和参考 token 覆盖率。
- test/features/lyrics/domain/proofreading/reference_token_aligner_test.dart：插入、软匹配、重复文本、无匹配、空参考和 DP 上限用例。
- docs/lyric_proofreading_v2_plan.md：标记已验证的 T1 完成，并把 T2 拆为 T2a/T2b。
- docs/work_log_index.md：把当前焦点更新为 T2a/T2b。
- docs/handoff.md：更新本次中断点。

## 检查结果

- 61eb74d 的 T1 日志记录：格式化通过、flutter analyze --no-pub 无问题、歌词域测试 221/221 通过、dart tool/work_log.dart check 通过。它们不是 T2a 的测试结果。
- 当前环境不能运行 Dart/Flutter；T2a 的 dart format、定向 flutter test、analyze 和完整歌词测试均未运行。
- 尚未添加 T2a 工作日志条目，也未手改生成文件 docs/work_log.md。

## 下一步（唯一）

在本地 Flutter 环境运行：dart format lib/features/lyrics/domain/proofreading/reference_token_aligner.dart test/features/lyrics/domain/proofreading/reference_token_aligner_test.dart；flutter test test/features/lyrics/domain/proofreading/reference_token_aligner_test.dart；flutter analyze --no-pub；flutter test test/features/lyrics；dart tool/work_log.dart write；dart tool/work_log.dart check。

若通过，再完成 T2a 日志并将 PR 标记为 Ready；之后再做 T2b 锚点链。

## 已知风险

- 本 PR 只有有界 DP，不包含唯一锚点；重复副歌歧义处理属于 T2b，不能把 T2 当作整体完成。
- DP cell 数超限时保守返回空匹配与 0 coverage，避免分配过大的矩阵，但长歌会进入 auto 策略低 coverage/fallback。
- 现有 T1 sanitizer 的 artist 参数目前未参与分类；当前记录的清洗规则只定义了 title 判断，后续调用前应先明确契约。

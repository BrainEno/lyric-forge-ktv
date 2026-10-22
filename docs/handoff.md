# Handoff

## 目标

推进歌词校对 V2 的 T2b：在 T2a 的有界 token DP 上加入唯一 n-gram 锚点候选和单调非重叠锚点链，并用锚点切分 DP 区间。重复副歌的高重复窗口不作为唯一锚点。

## Git 现场

- 本执行环境只有 GitHub 连接，没有本地 checkout；不能提供未经运行的本地 git status --short、git diff --stat 或 git log --oneline -5 输出。
- 当前远端 main HEAD（本次审查基线）：61eb74d388d491ef6a39816f74224f05ec725f2a。
- T2a Draft PR #133：https://github.com/BrainEno/lyric-forge-ktv/pull/133
- 当前堆叠分支：feat/lyric-proofreading-t2-anchor-chain-20261022；以 T2a 分支为 base。未创建 T2b PR 前不应将该分支直接合并 main。
- GitHub 未返回 T2a/T2b 当前提交的 status checks 或 Actions workflow runs。

## 已改文件

- lib/features/lyrics/domain/proofreading/reference_token_aligner.dart：唯一 n-gram occurrence 检查、有界候选集合、加权单调非重叠锚点链、锚点间 DP 和合并结果。
- test/features/lyrics/domain/proofreading/reference_token_aligner_test.dart：补充 Latin 唯一锚点、CJK 四 token 锚点、重复 chorus 不形成锚点和过大 DP 的断言。
- docs/handoff.md：更新到当前 T2b 中断点。

## 检查结果

- T1 记录在 main 上：格式化通过、flutter analyze --no-pub 无问题、歌词测试 221/221 通过、dart tool/work_log.dart check 通过；不是 T2b 验证。
- T2a 的 PR #133 以及本分支均未在当前环境运行 dart format、flutter test 或 analyze，因为没有本地 checkout 与 Dart/Flutter 可执行文件。
- 尚未添加 T2b 不可变任务日志条目，未手改生成文件 docs/work_log.md。

## 下一步（唯一）

将 T2b 作为 Draft PR 提交，base 指向 T2a 分支；然后在本地依次执行 T2a/T2b 的 formatter、定向测试、flutter analyze --no-pub、flutter test test/features/lyrics，以及 dart tool/work_log.dart write/check。只有这些实际通过后，才能写完成日志并把 PR 标记为 Ready。

## 已知风险

- 候选锚点链使用 O(n²) 加权链选择，n 受 maxChainCandidates=4000 限制；候选溢出时放弃锚点并回退到有界 DP。
- DP 分区总 cell 数超限时保留已经确认的锚点匹配，不执行剩余软匹配，因此覆盖率可能偏低；调用端必须检查 dpBudgetExceeded。
- T1 sanitizer 的 artist 参数未参与分类，后续消费者启用前仍需明确该参数契约。

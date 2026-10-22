# Handoff

## 目标

推进歌词校对 V2 的 T3：实现纯领域策略选择器，按 referenceFirst / asrFirst / auto 与 0.25 覆盖率阈值选择分支，并记录自动 fallback notes。

## Git 现场

- 本执行环境只有 GitHub 连接，没有本地 checkout；不能诚实提供本地 git status --short、git diff --stat 或 git log --oneline -5 输出。
- 已核实 GitHub main HEAD：969edef6f64b5cd89bf84b1e95c9989825df7efd。
- 工作分支：feat/lyric-proofreading-t3-strategy-selector-20261022；测试先行提交 7937060，选择器实现提交 373b8a1。
- GitHub 未返回该分支提交的 status checks 或 Actions workflow runs。

## 已改文件

- lib/features/lyrics/domain/proofreading/proofread_strategy_selector.dart：纯领域策略选择器及可解释决策。
- test/features/lyrics/domain/proofreading/proofread_strategy_selector_test.dart：无参考、阈值边界、低覆盖率回退、显式策略与非法 coverage。
- docs/lyric_proofreading_v2_plan.md：标记 T2a 已合并，并保留尚未出现在 main 的 T2b 状态。
- docs/work_log_index.md：将当前焦点更新到 T3。
- docs/handoff.md：更新本次中断点。

## 检查结果

- 用户已确认测试并合并先前的 T2 工作；但本次环境中 GitHub main@969edef 只包含 T2a 文件，T2b 锚点实现尚未出现在 main。
- T3 的 dart format、定向 flutter test、flutter analyze 与歌词域回归测试未运行：当前只有 GitHub 连接，没有本地 checkout 或 Dart/Flutter 可执行文件。
- 尚未添加 T3 不可变工作日志条目；未手改生成文件 docs/work_log.md。

## 下一步（唯一）

在本地运行 dart format lib/features/lyrics/domain/proofreading/proofread_strategy_selector.dart test/features/lyrics/domain/proofreading/proofread_strategy_selector_test.dart；再运行定向测试、flutter analyze --no-pub、flutter test test/features/lyrics，以及 dart tool/work_log.dart write/check。

验证通过后再写 T3 工作日志并将 PR 标记为 Ready；T3 只选择策略，不执行流水线，也不自行计算 coverage。

## 已知风险

- 当前 main 缺少 T2b 锚点链实现；T3 只接受已计算的 coverage，因此暂不直接调用对齐器。
- auto 有参考歌词时必须提供 0–1 的有限 coverage；输入缺失或非法会明确报错，不会静默选择策略。
- 现有 T1 sanitizer 的 artist 参数目前未参与分类；当前记录的清洗规则只定义了 title 判断，后续调用前应先明确契约。

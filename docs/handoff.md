# Handoff

## 目标

将唯一 n-gram 锚点链（T2b）引入当前 main；原 PR #134 只合入 T2a 功能分支，不能作为 main 已具备此能力的依据。

## Git 现场

- main 基线：`2cca83ad992d344325aa19d84b557d951b3a234f`；分支：`feat/lyric-proofreading-t2b-anchor-chain-main-20261022`。
- 测试先行提交：`2b487c8eb2c7f2783064171d879303af33fbb16e`；实现提交：`efe18c03a453a2ce8b042aaf4e01d281b6631380`；文档提交：`9726b565a8976dce8750a95654a67ee34b9be79d`。
- Draft PR #139 已创建。当前环境只有 GitHub API，没有本地 checkout / Dart / Flutter 工具链。

## 已改文件

- `reference_token_aligner.dart`：有界 Latin/CJK n-gram 候选、唯一性检查、加权单调非重叠锚点链、锚点间 DP。
- `reference_token_aligner_test.dart`：唯一锚点、顺序与重叠约束、重复副歌、DP 预算和候选溢出测试。
- `docs/lyric_proofreading_v2_plan.md`：标记已进入 main 的 T3 selector；T2b 保持待验证。
- `docs/work_log_index.md`：纠正 PR #136–#138 状态及当前焦点。
- `docs/handoff.md`：记录分支与验证要求。

## 检查结果

- 静态核对确认 main 已有 T2a aligner 与 T3 selector；本分支只补 T2b 缺失实现。
- 未运行 formatter、定向测试、analyze、歌词回归测试或 work-log 检查。
- 未创建不可变工作日志条目，未手工编辑生成文件 `docs/work_log.md`。

## 下一步（唯一）

本地运行 `dart format lib/features/lyrics/domain/proofreading/reference_token_aligner.dart test/features/lyrics/domain/proofreading/reference_token_aligner_test.dart`、定向 `flutter test test/features/lyrics/domain/proofreading/reference_token_aligner_test.dart`、`flutter analyze --no-pub`、`flutter test test/features/lyrics` 与 `dart tool/work_log.dart write/check)。全通过后再将 PR #139 标记为 Ready。

## 已知风险

- 候选链选择是 O(n²)，受 `maxChainCandidates` 限制；候选溢出时放弃锚点并退回有界 DP。
- 分区 DP 超预算时保留已确认锚点、不跑剩余软匹配，因此覆盖率可能偏低；调用端应检查 `dpBudgetExceeded`。

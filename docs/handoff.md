# Handoff

## 目标

把唯一 n-gram 锚点链（T2b）从原先只合入 T2a 功能分支的 PR #134 正确引入当前 main，避免后续 T4 使用缺失的锚点能力。

## Git 现场

- main 基线：`2cca83ad992d344325aa19d84b557d951b3a234f`。
- 工作分支：`feat/lyric-proofreading-t2b-anchor-chain-main-20261022`。
- 测试先行提交：`2b487c8eb2c7f2783064171d879303af33fbb16e`；实现提交：`efe18c03a453a2ce8b042aaf4e01d281b6631380`。
- 原 PR #134 目标为 T2a 分支，虽然已关闭为 merged，但锚点实现仍不在 main；本分支基于 main 重新承载实现，准备建立独立 Draft PR #139。

## 已改文件

- `test/features/lyrics/domain/proofreading/reference_token_aligner_test.dart`：覆盖唯一 Latin/CJK 锚点、顺序约束、重复副歌、DP 超限和锚点候选溢出。
- `lib/features/lyrics/domain/proofreading/reference_token_aligner.dart`：加入有界候选、唯一 n-gram 过滤、加权单调非重叠链与锚点间 DP。
- `docs/lyric_proofreading_v2_plan.md`：把已进入 main 的 T3 selector 标记完成；T2b 仍待验证。
- `docs/work_log_index.md`：纠正 PR #136–#138 状态并更新当前开发焦点。
- `docs/handoff.md`：记录当前分支、提交及验证限制。

## 检查结果

- 静态核对确认 main 已有 T2a aligner 与 T3 selector；本分支仅为 T2b 将锚点实现和测试补到 main 基线上。
- 未运行 `dart format`、定向 `flutter test`、`flutter analyze`、`flutter test test/features/lyrics` 或 work-log 检查：当前只有 GitHub API，没有本地 checkout / Dart / Flutter 工具链。
- 未创建不可变工作日志条目，也未手动修改生成文件 `docs/work_log.md`；需本地验证通过后再记录完成任务。

## 下一步（唯一）

在本地检出该分支，运行：

```powershell
dart format lib/features/lyrics/domain/proofreading/reference_token_aligner.dart test/features/lyrics/domain/proofreading/reference_token_aligner_test.dart
flutter test test/features/lyrics/domain/proofreading/reference_token_aligner_test.dart
flutter analyze --no-pub
flutter test test/features/lyrics
dart tool/work_log.dart write
dart tool/work_log.dart check
```

测试全部通过后再标记 PR #139 为 Ready。

## 已知风险

- 候选链选择为有界候选上的 O(n²) 加权链；候选超过 `maxChainCandidates` 时放弃锚点并回退为有界 DP。
- 分区 DP 预算超限时保留已确认锚点，但不再执行剩余软匹配，覆盖率可能偏低；调用方必须检查 `dpBudgetExceeded`。

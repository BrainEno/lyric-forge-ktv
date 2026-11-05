# Handoff

## 目标

继续处理 open P1 issue #317 的独立切片。本轮新增 genuinely secondary-only 韩文歌词回归：一行只出现在第二引擎输出、与共同歌词处于不同时间段时，在 Qwen-primary 与 Whisper-primary 两种次序下都应保留为低置信度、需人工复核的独有行。

## Git 现场

- Repository：`BrainEno/lyric-forge-ktv`
- 当前活动分支：`arena/f2ddfaf7-lyric-forge-ktv`
- 基线：`25305ee Merge pull request #354 ...`；PR #354 已 MERGED，最终 pinned Flutter Quality Gate `42040207163` 通过。
- PR #355：https://github.com/BrainEno/lyric-forge-ktv/pull/355，OPEN，head `137b5094409fac5f8e955335d7b4f2dfe5b413e0`；本地已调整新增测试的一种格式表达，待提交并重跑 gate。未授权不得合并。
- issue #317：https://github.com/BrainEno/lyric-forge-ktv/issues/317，仍 OPEN，尚有 chunk-merge 等验收未覆盖。
- 最近提交：`137b509 test: preserve Korean-only secondary lines`；本地未提交改动包含新的 formatter 调整及本 handoff/work-log 验证状态更新。

## 已改文件

- `test/high_quality_transcription_service_test.dart`：验证第二引擎独有的韩文行在两种 engine order 下保留，metadata secondary-only count/index 正确，confidence capped at 60 且标记为 heuristic。
- `docs/log/entries/2026-11-05-2313-keep-korean-secondary-lines.md`：记录该独立验收切片及当前 pinned CI 阻塞。
- `docs/work_log.md`、`docs/work_log_archive.md`、`docs/work_log_index.md`：更新任务导航。
- `docs/handoff.md`：本文。

## 检查结果

- `git diff --check` 通过。
- Pinned Quality Gate run `42053030878` 在 `Format check for changed Dart files` 失败，analyze/tests 未运行。GitHub Actions log 下载在当前环境失败，暂时无法看到 pinned formatter 的具体差异。
- 本地没有 Flutter/Dart SDK。
- PR #355 的最终 head 尚未通过 pinned gate，不得合并。

## 下一步

1. 提交并推送当前测试格式调整，重跑 PR #355 的 pinned Quality Gate；若格式检查仍失败，再取得 run 日志中的确切 formatter diff 并修正。确认最终 PR head 全绿后再推进 #317 下一切片；issue 未完整解决前保持打开，未经明确授权不得合并 PR。

## 已知风险

- 当前新回归测试已推送，但最终 pinned formatter 尚未通过；测试、analyze 均未执行。
- 本轮只覆盖普通 dual-engine merge 中 secondary-only 韩文行；分片合并路径尚未验证。
- issue #317 其余验收条件未完成，不得据此关闭 issue。
- Native builds、KTV recovery、runtime-release、icons 和其他 specialist workflows 尚未逐项审计。

最后更新：2026-11-05 23:15（Asia/Hong_Kong）

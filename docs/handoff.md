# Handoff

## 目标

继续处理 open P1 issue #317 的独立切片。本轮新增 genuinely secondary-only 韩文歌词回归：一行只出现在第二引擎输出、与共同歌词处于不同时间段时，在 Qwen-primary 与 Whisper-primary 两种次序下都应保留为低置信度、需人工复核的独有行。

## Git 现场

- Repository：`BrainEno/lyric-forge-ktv`
- 当前活动分支：`arena/f2ddfaf7-lyric-forge-ktv`
- 基线：`25305ee Merge pull request #354 ...`；PR #354 已 MERGED，最终 pinned Flutter Quality Gate `42040207163` 通过。
- PR #355：https://github.com/BrainEno/lyric-forge-ktv/pull/355，OPEN。代码 head `9356a6092c9863ed56091e7282b6691b2e1ca9d8` 的 pinned Quality Gate `42053995785` 已通过；本次 work-log/handoff 更新后需要查看新 head 检查状态。未经用户明确授权不得合并。
- issue #317：https://github.com/BrainEno/lyric-forge-ktv/issues/317，仍 OPEN，尚有 chunk-merge 等验收未覆盖。
- 最近代码提交：`9356a60 test: assert Korean-only secondary evidence`、`be10826 style: format Korean secondary-line test`、`137b509 test: preserve Korean-only secondary lines`。
- 当前工作区只有 work-log 与 handoff 的验证记录更新。

## 已改文件

- `test/high_quality_transcription_service_test.dart`：验证第二引擎独有的韩文行在两种 engine order 下保留，metadata secondary-only count/index 正确，confidence capped at 60 且标记为 heuristic。
- `docs/log/entries/2026-11-05-2313-keep-korean-secondary-lines.md`：记录该独立验收切片及 pinned CI 结果。
- `docs/work_log.md`、`docs/work_log_archive.md`、`docs/work_log_index.md`：更新任务导航。
- `docs/handoff.md`：本文。

## 检查结果

- `git diff --check` 通过。
- Pinned Flutter Quality Gate `42053995785` 在代码 head `9356a6092c9863ed56091e7282b6691b2e1ca9d8` 通过 work-log preflight、changed-file format、analyze 与全量测试。此前两次 formatter-only 失败已由简化断言格式修正。
- 本地没有 Flutter/Dart SDK；测试由 pinned CI 执行。

## 下一步

1. 提交并推送验证记录，确认 PR #355 新 head 的 pinned Quality Gate 通过；随后推进 #317 的 chunk-merge 独立切片。issue #317 未完整解决前保持打开，未经用户明确授权不得合并 PR。

## 已知风险

- 本轮只覆盖普通 dual-engine merge 中 secondary-only 韩文行；分片合并路径尚未验证。
- issue #317 其余验收条件未完成，不得据此关闭 issue。
- Native builds、KTV recovery、runtime-release、icons 和其他 specialist workflows 尚未逐项审计。

最后更新：2026-11-05 23:22（Asia/Hong_Kong）

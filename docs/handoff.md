# Handoff

## 目标

继续逐项完成 open P1 issue #317 的独立验收切片。本轮补齐共享 `LyricTokenizer` 对希腊扩展区的支持：U+1F00–U+1FFF 的 polytonic Greek 之前会被丢弃；现在比较层及双引擎服务测试覆盖该范围，并验证 Qwen-primary、Whisper-primary 两种顺序都不会重复插入相同歌词。

## Git 现场

- Repository：`BrainEno/lyric-forge-ktv`
- 当前活动分支：`arena/427bdf56-lyric-forge-ktv`
- 基线：`e5ffbf443a0681c09b71f6bcc4f258ddfb37e649`（PR #360 merge commit）。
- PR #360 已合并；本轮 PR #361：https://github.com/BrainEno/lyric-forge-ktv/pull/361，OPEN。
- 代码 head `1a9f1e5149fc5161a274f7e4120f284150e387fd` 的 pinned gate `42339604592` 全绿，包括 work-log preflight、changed-file format 和 repository quality gate。
- 本轮代码提交：`1a9f1e5 fix: preserve polytonic Greek in ASR matching`。
- issue #317：https://github.com/BrainEno/lyric-forge-ktv/issues/317，仍 OPEN。Issue checklist 上次编辑返回 HTTP 403 `Resource not accessible by integration`，尚未在线同步。
- PR #361 没有获合并授权；其他 PR 的授权不适用于此 PR。

## 已改文件

- `lib/features/lyrics/domain/proofreading/lyric_tokenizer.dart`：识别 Greek Extended U+1F00–U+1FFF。
- `test/asr_text_comparison_test.dart`：验证 polytonic Greek 字符保留且不同字符仍有相似度差异。
- `test/high_quality_transcription_service_test.dart`：两种 engine order 下验证匹配的 Greek Extended 文本只保留一行。
- `docs/log/entries/2026-11-07-1245-preserve-greek-extended-asr.md`：本轮切片和 CI 记录。
- `docs/work_log.md`、`docs/work_log_archive.md`：生成式工作日志导航。
- `docs/work_log_index.md`：更新 ASR Unicode 覆盖索引。
- `docs/handoff.md`：本文。

## 检查结果

- `git diff --check` 通过。
- Pinned Flutter Quality Gate `42339604592` 在代码 head `1a9f1e5` 全绿；work-log preflight、格式检查、repository quality gate 均通过。
- 本地没有 Flutter/Dart SDK；analyze/test 由 pinned CI 执行。文档更新若推进 PR head，合并前须确认最新 head 的 gate。

## 下一步

1. PR #361、issue #317 均保持 OPEN；没有用户授权前不合并、不关闭。
2. 继续审计 issue #317 的验收范围，每次只推进一个独立切片；issue 在线 checklist 仅在写入权限恢复后同步。

## 已知风险

- 本轮补 Greek Extended；Latin Extended 的全部 Unicode 子区段、Cyrillic 扩展区和其他低频文字范围仍可继续审计，不能将本轮视为 Unicode 全覆盖。
- 本地无法运行 Flutter tests/analyze；CI 是本轮测试依据。
- 真实歌曲 recall/WER 仍需人工核对语料；Native builds、KTV recovery、runtime release、icons 等 specialist workflows 尚未审计。

最后更新：2026-11-07 12:45（Asia/Taipei）

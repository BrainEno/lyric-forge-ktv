# Handoff

## 目标

继续逐项完成 open P1 issue #317 的独立验收切片。本轮补齐 tokenizer 对 Cyrillic Supplement/Extended 区段的识别，包括 Cyrillic combining marks，避免扩展西里尔歌词被丢弃或合并标记消失。比较层与双引擎服务测试覆盖各目标区段及 Qwen-primary、Whisper-primary 两种顺序。PR #361 还包含前一项 Greek Extended 切片。

## Git 现场

- Repository：`BrainEno/lyric-forge-ktv`
- 当前活动分支：`arena/427bdf56-lyric-forge-ktv`
- 基线：`e5ffbf443a0681c09b71f6bcc4f258ddfb37e649`（PR #360 merge commit）。
- PR #360 已合并；PR #361：https://github.com/BrainEno/lyric-forge-ktv/pull/361，OPEN。
- 本轮代码 head `4fb9b8b3981a146c005a7cd3c656bcb1c321b88e` 的 pinned gate `42340288906` 全绿，包括 work-log preflight、changed-file format 和 repository quality gate。文档提交推进 head 后，合并前仍要确认最新 PR head 的 gate。
- 本轮代码提交：`4fb9b8b fix: preserve Cyrillic extensions in ASR matching`；本 PR 先前代码提交：`1a9f1e5 fix: preserve polytonic Greek in ASR matching`。
- issue #317：https://github.com/BrainEno/lyric-forge-ktv/issues/317，仍 OPEN。Issue checklist 上次编辑返回 HTTP 403 `Resource not accessible by integration`，尚未在线同步。
- PR #361 没有获合并授权；PR #360 已合并不代表授权本 PR。

## 已改文件

- `lib/features/lyrics/domain/proofreading/lyric_tokenizer.dart`：保留 Cyrillic Supplement、Extended-B/C/D、Extended-A combining marks 字符。
- `test/asr_text_comparison_test.dart`：覆盖各扩展区及 combining mark 的文本归一化。
- `test/high_quality_transcription_service_test.dart`：两种 engine order 下验证扩展西里尔行正确去重。
- `docs/log/entries/2026-11-07-1255-preserve-cyrillic-extended-asr.md`：本轮切片及 CI 记录。
- `docs/work_log.md`、`docs/work_log_archive.md`：生成式工作日志导航。
- `docs/work_log_index.md`：补充当前 Unicode 支持范围。
- `docs/handoff.md`：本文。

## 检查结果

- `git diff --check` 通过。
- Pinned Flutter Quality Gate `42340288906` 在代码 head `4fb9b8b` 全绿；work-log preflight、changed-file format、repository quality gate 均通过。
- 本地没有 Flutter/Dart SDK；analyze/test 由 pinned CI 执行。

## 下一步

1. PR #361、issue #317 均保持 OPEN；没有用户授权前不合并、不关闭。
2. 继续逐项审计 issue #317 的字符范围和验收覆盖；Latin Extended 子区段仍值得单独核对。issue 在线 checklist 仅在写入权限恢复后同步。
3. 若分支前进，合并前检查当前 PR head 的 pinned gate。

## 已知风险

- 当前补齐了西里尔补充/扩展区；Latin Extended 的全部 Unicode 子区段和其他低频书写系统仍可继续审计，不能声称 Unicode 全覆盖。
- 本地无法运行 Flutter tests/analyze；CI 是本轮测试依据。
- 真实歌曲 recall/WER 仍需人工核对语料；Native builds、KTV recovery、runtime release、icons 等 specialist workflows 尚未审计。

最后更新：2026-11-07 12:55（Asia/Taipei）

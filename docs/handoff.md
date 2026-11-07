# Handoff

## 目标

继续逐项完成 open P1 issue #317 的独立验收切片。本轮修复共享 `LyricTokenizer` 丢弃补充平面汉字的问题：现已覆盖 Unicode 17.0 CJK Unified Ideograph Extensions B–J（Extension I 的区段不连续），并添加比较层及双引擎融合回归，检查 Extension B/J 不再归一化为空，且重复歌词在 Qwen-primary、Whisper-primary 两种顺序下均被匹配。

## Git 现场

- Repository：`BrainEno/lyric-forge-ktv`
- 活动分支：`arena/79c0281f-lyric-forge-ktv`
- 基线：`39949d97d3b53bf3a3870acf24b14d2a3328a6e4`（PR #359 merge commit）。
- PR #359 已合并；PR #360：https://github.com/BrainEno/lyric-forge-ktv/pull/360，保持 OPEN。
- 最新代码 head `57fae63845a29f4eeeec857271d20a20f17aebbf` 的 pinned gate `42332246659` 全绿；包含 work-log/handoff 的后续 head 也应在合并前通过自己的 gate。
- 本轮代码提交：`84ceca5 fix: preserve supplementary CJK ideographs`；格式 follow-up：`57fae63 style: format supplementary CJK regression test`。
- issue #317：https://github.com/BrainEno/lyric-forge-ktv/issues/317，仍 OPEN。Issue 在线清单上次编辑返回 HTTP 403 `Resource not accessible by integration`，尚未同步。
- PR #360 尚未获合并授权；PR #358/#359 的授权不适用于此 PR。

## 已改文件

- `lib/features/lyrics/domain/proofreading/lyric_tokenizer.dart`：识别当前补充平面 CJK 统一表意文字区段。
- `test/asr_text_comparison_test.dart`：验证 Extension B/J 保留且不同文本仍有差异。
- `test/high_quality_transcription_service_test.dart`：两种 engine order 下验证相同补充平面汉字只保留一行。
- `docs/log/entries/2026-11-07-1107-preserve-supplementary-cjk-asr.md`：本轮切片与 CI 记录。
- `docs/work_log.md`、`docs/work_log_archive.md`：生成式工作日志导航。
- `docs/work_log_index.md`：补充 ASR Unicode 覆盖范围索引。
- `docs/handoff.md`：本文。

## 检查结果

- `git diff --check` 通过。
- 初始代码 head `84ceca5` 的 pinned gate `42332144479` 在 changed-file format 阶段失败，未运行测试；Actions 日志下载返回 EOF。格式 follow-up 后，`57fae63` 的 gate `42332246659` 全绿，包括 work-log preflight、changed-file format 和 repository quality gate。
- 本地没有 Flutter/Dart SDK；analyze/test 由 pinned CI 执行。
- 上述全绿 gate 验证本轮代码；文档提交后如 PR head 前进，合并前仍须检查当前 head 的 gate。

## 下一步

1. 保持 PR #360、issue #317 均 OPEN；没有获得授权前不合并、不关闭。
2. 继续审计 issue #317 的验收范围，每次只推进一个独立切片；只有在 issue 写入权限恢复后才同步线上 checklist。

## 已知风险

- 扩展区段使用 Unicode 17.0 的明确块边界；本轮覆盖 Extension B 与最新 Extension J 的比较层行为，另以服务测试验证 Extension B 双引擎融合。
- 本地无法运行 Flutter tests/analyze；CI 是本轮测试依据。
- 真实歌曲 recall/WER 仍需人工核对语料；Native builds、KTV recovery、runtime release、icons 等 specialist workflows 尚未审计。

最后更新：2026-11-07 11:07（Asia/Taipei）

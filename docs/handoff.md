# Handoff

## 目标

继续逐项完成 open P1 issue #317 的独立验收切片。本轮补充服务级 canonical-decomposition 回归：Qwen 输出预组合 `Tiếng Việt`，Whisper 输出等价的分解序列 `Tie\u0302\u0301ng Vie\u0323\u0302t`；Qwen-primary 与 Whisper-primary 两种顺序均应匹配成一行，不产生 secondary-only 行或分歧候选。

## Git 现场

- Repository：`BrainEno/lyric-forge-ktv`
- 当前活动分支：`arena/79c0281f-lyric-forge-ktv`
- 基线：`39949d97d3b53bf3a3870acf24b14d2a3328a6e4`（PR #359 merge commit）。
- PR #359 已合并；PR #360：https://github.com/BrainEno/lyric-forge-ktv/pull/360，OPEN。
- PR #360 的代码 head `b81a30c380d99923e58479a81f5851565e3ecacd` pinned gate `42259148984` 全绿；随后包含 work-log/handoff 的 head `155a76ef133ead973d4807cf5e39a1cb6509bd9b` 也由 gate `42259788725` 全绿。若分支之后再前进，合并前仍须确认当前 PR head 的 gate 通过。
- 代码提交：`5294d3f test: cover decomposed Vietnamese ASR fusion`，格式 follow-up：`b81a30c test: simplify decomposed Vietnamese fusion assertions`。
- issue #317：https://github.com/BrainEno/lyric-forge-ktv/issues/317，仍 OPEN。上一轮 issue 编辑返回 HTTP 403 `Resource not accessible by integration`，在线清单仍未同步。
- PR #360 尚未获合并授权；PR #358/#359 的合并授权不适用于此 PR。

## 已改文件

- `test/high_quality_transcription_service_test.dart`：新增越南语预组合与 canonically decomposed 对照，在两种 engine order 下验证融合结果。
- `docs/log/entries/2026-11-07-0113-match-decomposed-vietnamese-asr.md`：本轮切片与 CI 记录。
- `docs/work_log.md`、`docs/work_log_archive.md`：生成式工作日志导航。
- `docs/handoff.md`：本文。

## 检查结果

- `git diff --check` 通过。
- 初始代码 head `5294d3f` 的 gate `42258479008` 在 changed-file format 阶段失败，未运行测试；详细 Actions 日志下载返回 EOF。
- 调整断言后的代码 head `b81a30c` gate `42259148984` 全绿，包括 work-log preflight、changed-file format 和 repository quality gate。
- 本地没有 Flutter/Dart SDK；analyze/test 由 pinned CI 执行。包含本轮 work-log/handoff 的 head `155a76e` 已通过 gate `42259788725`；之后若有新提交，需检查新的当前 head gate。

## 下一步

1. PR #360 保持 OPEN，等待用户授权后再合并；若再有任何提交，先确认当前 PR head 的 pinned gate 通过。
2. Issue #317 保持 OPEN；继续一项一项验证剩余范围，且不要在 HTTP 403 权限问题解决前声称已在线更新 issue checklist。

## 已知风险

- 预组合/分解越南语样例已在代码 head 的 full pinned gate 通过；文档更新后的最终 head 仍需再次验证。
- issue #317 的在线 checklist 编辑此前返回 HTTP 403；问题正文尚未同步。
- 真正歌曲 recall/WER 仍需人工核对语料；Native builds、KTV recovery、runtime release、icons 等 specialist workflows 尚未审计。

最后更新：2026-11-07 01:18（Asia/Taipei）

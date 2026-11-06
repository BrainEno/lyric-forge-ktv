# Handoff

## 目标

继续逐项完成 open P1 issue #317 的独立验收切片。本轮 PR #358 增加双引擎服务级空归一化回归：两条原始文本都非空但规范化均为空时，不得误认为已匹配；两种引擎次序下，primary 行应保留，未匹配的 secondary 行应作为 review-only 行呈现，不得伪造 disagreement candidate。为恢复 PR 的 pinned quality gate，本轮也处理了反复失败的 Media Hub total-upload-deadline 测试时序问题。

## Git 现场

- Repository：`BrainEno/lyric-forge-ktv`
- 当前活动分支：`arena/6ce0328f-lyric-forge-ktv`
- 基线：`6334286733df4f383f4ddcfd774e8893be750deb`（PR #357 合并提交）；PR #356/#357 已合并。
- PR #358：https://github.com/BrainEno/lyric-forge-ktv/pull/358，OPEN。最新已推送代码 head `f51df14c4a282ce938a5aef94d04c4236e9463bf` 的 pinned gate `42170184620` 全绿。随后新增的验证记录/work-log/handoff 变更还需推送，并在合并前确认精确最终 head 的 gate 也全绿。
- issue #317：https://github.com/BrainEno/lyric-forge-ktv/issues/317，仍 OPEN。
- 本切片回归提交：`df68766 test: keep empty-normalized ASR rows unmatched`。Media Hub 测试时序更新提交：`f51df14 test: widen Media Hub total deadline test margin`。
- 用户已明确要求合并 PR #358，但最终 PR-head pinned CI 必须先通过；合并后 issue #317 仍保持 OPEN。

## 已改文件

- `test/high_quality_transcription_service_test.dart`：在 Qwen-primary 与 Whisper-primary 次序下验证两条非空但规范化为空的文本不被视作匹配；primary 保留，secondary 作为 review-only 行。
- `test/features/transfer/http_media_hub_upload_test.dart`：总 timeout 5 秒、idle timeout 30 秒；继续发送 chunk 最多 200 × 30 ms，并允许 15 秒读取响应；断言 deadline 前确有后续 chunk 发送。
- `docs/log/entries/2026-11-06-1003-empty-normalized-fusion-regression.md`、`docs/log/entries/2026-11-06-1337-stabilize-media-hub-total-upload-deadline.md`、`docs/log/entries/2026-11-06-1343-widen-media-hub-total-upload-deadline.md`、`docs/log/entries/2026-11-06-1347-verify-media-hub-deadline-gate.md`：记录回归、失败和通过的 gate。
- `docs/work_log.md`、`docs/work_log_archive.md`：生成式工作日志导航。
- `docs/handoff.md`：本文。

## 检查结果

- 最近一次完整 pinned gate `42170184620`（head `f51df14c4a282ce938a5aef94d04c4236e9463bf`）全绿，包括 work-log preflight、changed-file formatting 和 repository quality gate。
- 前一 head `a185b01c46c1f7c310a6d0c91ebf6a07d210d54e` 的 gate `42169695799` 仍在同一 Media Hub 测试失败（1170 通过、1 失败）；当时使用 1 秒 total / 3 秒 idle。5 秒 total / 30 秒 idle 的后续 head已通过完整 gate 一次。
- `42169695799` 的详细失败日志下载返回 EOF，GitHub annotations 只报告测试失败，没有 assertion 详情。本地没有 Flutter/Dart SDK；analyze/test 均由 pinned CI 执行。

## 下一步

1. 提交并推送本次 work-log/handoff 验证记录；等待它触发的最终 PR-head gate。
2. 只有最新精确 head 的 pinned gate 全绿时，才按用户授权执行 `gh pr merge 358 --merge`。若门禁失败，继续检查，不得绕过测试。
3. 合并后仍保持 issue #317 OPEN；继续逐项核对其余验收条件，完成前不要关闭 issue。

## 已知风险

- 5 秒/30 秒 timing-margin 方案目前有一次完整 pinned gate 通过；后续文档 head 会再次跑全套门禁，提供第二次验证。
- 未能取得 `42169695799` 的详细 assertion 日志，确切的先前失败断言未知。
- 当前只验证双引擎融合中 empty-normalized 文本的匹配边界；真实歌曲召回率/WER 仍需人工校验语料。
- issue #317 保持 OPEN，需复核全部验收标准后再决定其状态。
- Native builds、KTV recovery、runtime release、icons 和其他 specialist workflows 尚未逐项审计。

最后更新：2026-11-06 13:47（Asia/Taipei）

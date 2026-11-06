# Handoff

## 目标

继续逐项完成 open P1 issue #317 的独立验收切片。本轮 PR #358 增加双引擎服务级空归一化回归：两条原始文本都非空但规范化均为空时，不得误认为已匹配；两种引擎次序下，primary 行应保留，未匹配的 secondary 行应作为 review-only 行呈现，不得伪造 disagreement candidate。为恢复 PR 的 pinned quality gate，本轮还修复了反复失败的 Media Hub total-upload-deadline 测试时序脆弱问题。

## Git 现场

- Repository：`BrainEno/lyric-forge-ktv`
- 当前活动分支：`arena/6ce0328f-lyric-forge-ktv`
- 基线：`6334286733df4f383f4ddcfd774e8893be750deb`（PR #357 合并提交）；PR #356/#357 已合并。
- PR #358：https://github.com/BrainEno/lyric-forge-ktv/pull/358，OPEN。代码提交 `d06c94efebb20193923dec4a0c38f1667f749649` 的 pinned gate `42169233340` 已通过 work-log preflight、changed-file format 和 repository quality gate。本次工作日志/handoff 更新会进入后续 PR-head gate；合并前必须确认最终 head 的 gate 为 green。
- issue #317：https://github.com/BrainEno/lyric-forge-ktv/issues/317，仍 OPEN。
- 本切片代码提交：`df68766 test: keep empty-normalized ASR rows unmatched`；gate 修复提交：`d06c94e test: stabilize Media Hub total upload deadline regression`。
- 用户已明确要求合并 PR #358，但最终 PR-head pinned CI 必须先通过。不得因先前代码 head 的绿灯而跳过文档提交后的最终 gate。

## 已改文件

- `test/high_quality_transcription_service_test.dart`：在 Qwen-primary 与 Whisper-primary 次序下验证两条非空但规范化为空的文本不被视作匹配；primary 保留，secondary 作为 review-only 行。
- `test/features/transfer/http_media_hub_upload_test.dart`：把总上传 deadline 从 250 ms 放宽到 1 s、idle timeout 从 2 s 调整为 3 s，为 loopback TLS/CI 负载留出空间；断言 408 前确有后续 chunk 发送。
- `docs/log/entries/2026-11-06-1003-empty-normalized-fusion-regression.md`、`docs/log/entries/2026-11-06-1337-stabilize-media-hub-total-upload-deadline.md`：记录两个独立切片及验证结果。
- `docs/work_log.md`、`docs/work_log_archive.md`：生成式工作日志导航更新。
- `docs/handoff.md`：本文。

## 检查结果

- `git diff --check` 通过。
- 最新已完成 pinned gate `42169233340`（head `d06c94efebb20193923dec4a0c38f1667f749649`）全绿，包括 work-log preflight、Dart changed-file formatting、repository quality gate。
- 此前三个 head 的 gate（`42147456078`、`42147925809`、`42148380426`）均在同一个 Media Hub deadline 测试失败；首个结果显示 1170 通过、1 失败。新测试修复在 `42169233340` 全量门禁通过。
- 本地没有 Flutter/Dart SDK；analyze/test 由 pinned CI 执行。上面的 code-head gate 不验证新增的文档/交接更新；合并前要确认包含这些更新的最终 PR head 也通过 pinned gate。

## 下一步

1. 更新并推送本次 work-log/handoff，然后等待新的 PR #358 pinned gate 完成；仅当该最终 head 全绿时，按用户授权执行 `gh pr merge 358 --merge`。
2. 合并后仍保持 issue #317 OPEN；继续逐项核对其余验收条件，完成前不要关闭 issue。

## 已知风险

- 当前只验证双引擎融合中 empty-normalized 文本的匹配边界；真实歌曲召回率/WER 仍需人工校验语料。
- issue #317 保持 OPEN，需复核全部验收标准后再决定其状态。
- Native builds、KTV recovery、runtime release、icons 和其他 specialist workflows 尚未逐项审计。

最后更新：2026-11-06 13:37（Asia/Taipei）

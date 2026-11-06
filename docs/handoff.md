# Handoff

## 目标

继续逐项完成 open P1 issue #317 的独立验收切片。本轮 PR #358 增加双引擎服务级空归一化回归：两条原始文本都非空但规范化均为空时，不得误认为已匹配；两种引擎次序下，primary 行应保留，未匹配的 secondary 行应作为 review-only 行呈现，不得伪造 disagreement candidate。为恢复 PR 的 pinned quality gate，本轮也在处理反复失败的 Media Hub total-upload-deadline 测试时序脆弱问题。

## Git 现场

- Repository：`BrainEno/lyric-forge-ktv`
- 当前活动分支：`arena/6ce0328f-lyric-forge-ktv`
- 基线：`6334286733df4f383f4ddcfd774e8893be750deb`（PR #357 合并提交）；PR #356/#357 已合并。
- PR #358：https://github.com/BrainEno/lyric-forge-ktv/pull/358，OPEN。最新已推送 head `a185b01c46c1f7c310a6d0c91ebf6a07d210d54e` 的 pinned gate `42169695799` 仍因 Media Hub total-upload-deadline 测试失败；工作区有后续时序加宽修改，尚未提交/推送。不得合并，直到最终 PR-head gate 全绿。
- issue #317：https://github.com/BrainEno/lyric-forge-ktv/issues/317，仍 OPEN。
- 本切片回归提交：`df68766 test: keep empty-normalized ASR rows unmatched`。Media Hub 测试时序修复尝试：`d06c94e test: stabilize Media Hub total upload deadline regression`；对应 docs commit `a185b01`。
- 用户已明确要求合并 PR #358，但最终 PR-head pinned CI 必须先通过；合并后 issue #317 仍保持 OPEN。

## 已改文件

- `test/high_quality_transcription_service_test.dart`：在 Qwen-primary 与 Whisper-primary 次序下验证两条非空但规范化为空的文本不被视作匹配；primary 保留，secondary 作为 review-only 行。
- `test/features/transfer/http_media_hub_upload_test.dart`：当前未提交修改把 total timeout 加宽到 5 s、idle timeout 加宽到 30 s，继续发 chunk 的测试循环最多运行 200 × 30 ms，并给响应读取 15 s；断言在 deadline 前确有后续 chunk 发送。
- `docs/log/entries/2026-11-06-1003-empty-normalized-fusion-regression.md`、`docs/log/entries/2026-11-06-1337-stabilize-media-hub-total-upload-deadline.md`、`docs/log/entries/2026-11-06-1343-widen-media-hub-total-upload-deadline.md`：记录回归和 gate 修复尝试。
- `docs/work_log.md`、`docs/work_log_archive.md`：生成式工作日志导航。
- `docs/handoff.md`：本文。

## 检查结果

- `git diff --check` 通过（当前未提交测试修改）。
- Pinned gate `42169233340`（head `d06c94efebb20193923dec4a0c38f1667f749649`）曾全绿；但包含文档更新的后续 gate `42169695799`（head `a185b01c46c1f7c310a6d0c91ebf6a07d210d54e`）再次在同一个 Media Hub 测试失败，1170 项通过、1 项失败。该 run 的注解未带 assertion 详情，Actions log 下载也返回 EOF；不能将此前单次绿灯视为修复已验证。
- 本地没有 Flutter/Dart SDK；analyze/test 由 pinned CI 执行。工作区的 5 s/30 s 延长方案尚未经过 CI。

## 下一步

1. 检查当前 test diff，提交并推送这次 timing-margin follow-up；等待该 head 的 pinned gate。若仍失败，继续查清测试 assertion/timeout 根因；不得绕过或忽略该测试。
2. 仅当包含所有代码和文档的最终 PR #358 head 全绿时，按用户授权执行 `gh pr merge 358 --merge`。
3. 合并后仍保持 issue #317 OPEN；继续逐项核对其余验收条件，完成前不要关闭 issue。

## 已知风险

- Media Hub deadline regression 至少一个 CI run 仍失败，确切 assertion 详情因 Actions log 下载 EOF 暂不可见；当前加宽方案未验证。
- 当前只验证双引擎融合中 empty-normalized 文本的匹配边界；真实歌曲召回率/WER 仍需人工校验语料。
- issue #317 保持 OPEN，需复核全部验收标准后再决定其状态。
- Native builds、KTV recovery、runtime release、icons 和其他 specialist workflows 尚未逐项审计。

最后更新：2026-11-06 13:43（Asia/Taipei）

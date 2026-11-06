# Handoff

## 目标

继续逐项完成 open P1 issue #317 的独立验收切片。本轮在 dual-engine service regression 中补充越南语扩展拉丁字符：Qwen `Tiếng Việt` 对 Whisper `Tieng Viet`，并覆盖 Qwen-primary 与 Whisper-primary 两种顺序，验证不产生重复 secondary-only 行或假分歧候选。

## Git 现场

- Repository：`BrainEno/lyric-forge-ktv`
- 当前活动分支：`arena/5232659b-lyric-forge-ktv`
- 基线：`64c52d8ca977ecc128b3fa0ab143a409e5595e31`（PR #358 merge commit）。
- PR #358 已合并；issue #317 仍 OPEN：https://github.com/BrainEno/lyric-forge-ktv/issues/317。
- PR #359：https://github.com/BrainEno/lyric-forge-ktv/pull/359，OPEN。源代码 head `d0302e49873f005e470fb8c131361df852595886` 的 gate `42214638985` 通过；含 work-log/handoff 的 head `b85766743cf6aa0f394eff76fd72fa64c139ff12` 的 gate `42215131646` 也全绿。
- 代码提交：`d0302e4 test: cover Vietnamese ASR fusion normalization`；工作日志提交：`b857667 docs: record Vietnamese ASR fusion regression`。
- PR #359 尚未获合并授权，保持 OPEN。
- 上一轮尝试编辑 issue #317 checklist 时，GitHub 返回 HTTP 403 `Resource not accessible by integration`；issue 未被修改或关闭。等待用户恢复 issue 写入权限后再同步清单。

## 已改文件

- `test/high_quality_transcription_service_test.dart`：在多语种双引擎 service regression 中增加越南语扩展拉丁字符 `Tiếng Việt` / `Tieng Viet`；两种 engine order 都检查无重复行、无 disagreement candidate。
- `docs/log/entries/2026-11-06-2005-cover-vietnamese-asr-fusion.md`：本轮切片记录。
- `docs/work_log.md`、`docs/work_log_archive.md`：生成式工作日志导航。
- `docs/handoff.md`：本文。

## 检查结果

- `git diff --check` 通过。
- Pinned Flutter Quality Gate `42214638985`（代码 head `d0302e49873f005e470fb8c131361df852595886`）和 `42215131646`（含工作日志的 head `b85766743cf6aa0f394eff76fd72fa64c139ff12`）均全绿；包括 work-log preflight、changed-file format 与 repository quality gate。
- 本地没有 Flutter/Dart SDK；analyze/test 由 pinned CI 执行。

## 下一步

1. 维持 PR #359 OPEN，等待用户决定是否合并；不要把 PR #358 的合并授权延伸到 #359。
2. 继续 issue #317 下一项独立切片，或在 GitHub issue 写入权限恢复后同步验收清单。Issue 的在线 checklist 目前仍未更新。
3. issue #317 所有验收及所需实际语料验证完成前保持 OPEN。

## 已知风险

- 越南语回归覆盖预组合扩展拉丁重音的服务级双引擎匹配；更广泛的真实歌曲召回率/WER 仍需人工核对语料。
- issue #317 的在线 checklist/issue 状态目前不能编辑（HTTP 403）；本轮代码和测试变更未受影响。
- Native builds、KTV recovery、runtime release、icons 等 specialist workflows 尚未审计。

最后更新：2026-11-06 20:09（Asia/Taipei）

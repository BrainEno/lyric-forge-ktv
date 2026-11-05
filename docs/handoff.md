# Handoff

## 目标

处理 P1 issue #331，避免双引擎 ASR fusion 将 unscored 占位分数或 heuristic 调整分数当作可直接比较的 model confidence，从而自动替换主引擎歌词。Issue #331 当前仍 OPEN；用户要求完成并尽可能关闭。

## Git 现场

- Repository：`BrainEno/lyric-forge-ktv`
- 当前活动分支：`arena/3f7a3c14-lyric-forge-ktv`。
- 实现提交：`1552fa5 fix: require model confidence for automatic ASR fusion`；后续格式布局提交：`9f01c7b style: preserve pinned formatter layout in fusion tests`。
- PR #351：<https://github.com/BrainEno/lyric-forge-ktv/pull/351>，OPEN；未授权合并。
- Pinned Flutter Quality Gate run `42012105849` 在代码/测试 head `9f01c7b` 通过，包含 work-log preflight、changed-Dart format、analyzer 与全量 repository tests。后续 work-log/handoff 更新后，必须确认 PR 最新 head 的 Quality Gate。

## 已改文件

- `lib/features/transcription/data/services/high_quality_transcription_service.dart`：两条自动替换路径均要求 Qwen/Whisper 两侧 confidence source 都是 `model`；多行 fallback 的 provenance 聚合采用保守策略：任意 unscored 则 aggregate unscored，否则任意 heuristic 则 aggregate heuristic。
- `test/high_quality_transcription_service_test.dart`：覆盖两种 engine order、双方 unscored、单侧 unscored、model/heuristic 混合及保留人工 review candidate。
- `docs/log/entries/2026-11-05-1833-require-model-confidence-for-asr-fusion.md` 与生成的 work-log navigation。

## 检查结果

- `git diff --check` 通过。
- 代码/测试实现 head 的 pinned Flutter Quality Gate run `42012105849` 通过；本地没有 Flutter/Dart SDK。
- 一次早期 CI head 因 WASM formatter 改写了原本 pinned formatter 布局而在 format check 失败；已恢复无关旧代码布局，后续 run `42012105849` 完整通过。
- 当前 work-log/handoff 文档提交需要新的 PR head gate；以 GitHub PR #351 最新 checks 为准。

## 下一步

1. 提交并推送 work-log/handoff 更新，确认 PR #351 最新 head 的 pinned Flutter Quality Gate 全绿。
2. 若检查通过，按用户授权关闭 issue #331；若权限拒绝关闭，则把 issue 链接发给用户手动关闭：<https://github.com/BrainEno/lyric-forge-ktv/issues/331>。
3. PR #351 保持 OPEN，未经用户明确授权不得合并。

## 已知风险

- 由于要求 source 严格等于 `model`，heuristic provenance 即使底层原本有模型分数也只会生成 review candidate，不会自动替换；这是有意的保守策略。
- 本地无 Flutter/Dart SDK；验证依赖 pinned CI。
- native、KTV recovery、runtime-release、icon 和其他 specialist workflows 未逐项审计。

最后更新：2026-11-05（Asia/Hong_Kong）

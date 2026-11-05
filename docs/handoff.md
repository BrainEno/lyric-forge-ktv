# Handoff

## 目标

本轮先修复 PR #350 Flutter Quality Gate 中 `test/features/transfer/http_media_hub_upload_test.dart` 的 TLS 握手 `Broken pipe`：仅在测试 helper 中对 transient EPIPE 做有限重试，避免 CI 负载下握手被短暂复位；其余 socket/TLS 错误仍会失败。PR #350 原切片同时将 ForcedAligner 不支持项目语言时的用户提示移出 domain，保留原文并在 presentation 显示。

## Git 现场

- Repository：`BrainEno/lyric-forge-ktv`
- 当前活动分支：`arena/935b04e1-lyric-forge-ktv`。
- 基线：PR #349 已合并，merge commit `c79538af183b47b805a2e692dccd7974b9cef817`。
- 本轮代码提交：`55ceb4d refactor: move ForcedAligner language guidance to presentation`；`f68cd80 test: retry transient Media Hub TLS broken pipes`。
- PR #350：<https://github.com/BrainEno/lyric-forge-ktv/pull/350>，OPEN；没有本 PR 的合并授权。
- 最新代码/测试 head `f68cd80400a7dcc366857fa8618e4ec86d9a4eb8` 的 pinned Flutter Quality Gate run `42008920419` 通过，包含 work-log preflight、changed-Dart format、analysis 和全量 tests。文档提交会更新 PR head；合并前始终检查最新 head 的 gate。
- 较早 PR head 的 runs `42005165752` 与 `42006114278` 均因同一 Media Hub upload deadline 测试在 `SecureSocket.connect` 处 Broken pipe 失败；测试 helper 已增加仅针对 EPIPE 的有限退避重试。无生产 Media Hub 服务改动。
- PR #348/#349 的合并状态及授权仅适用于各自 PR，不授权合并 #350。Issue #335 保持 CLOSED。

## 已改文件

- `test/features/transfer/http_media_hub_upload_test.dart`：`_openPinnedSocket` 对 Linux errno 32 / `Broken pipe` 最多重试 3 次，延迟逐次增加且有界；证书错误、其他 socket 错误和持续 EPIPE 不被吞掉。
- `lib/features/lyrics/domain/proofreading/forced_alignment_language.dart`：用 `ForcedAlignmentLanguageResolutionException` 保留不支持的原始语言，不再拼接用户提示。
- `lib/features/lyrics/presentation/lyric_review_strings.dart`：映射原有 ForcedAligner 语言指导文案。
- `lib/features/lyrics/presentation/screens/lyric_editor_screen.dart`：只对该 typed exception 使用 presentation 文案，其余异常维持既有处理。
- domain 与 presentation tests 覆盖 typed failure data 及原提示文案。
- `docs/log/entries/2026-11-05-1745-move-forced-aligner-language-guidance-to-presentation.md`、`docs/log/entries/2026-11-05-1816-stabilize-media-hub-upload-tls-test.md` 及 work-log 导航记录相关切片。

## 检查结果

- `git diff --check` 通过；临时 WASM `@wasm-fmt/dart_fmt` 对改动 Dart 文件的格式检查通过。
- 本地没有 Flutter/Dart SDK，未运行本地 tests。
- Pinned Flutter Quality Gate run `42008920419` 在代码/测试 head `f68cd80` 通过全量 tests、分析、format 和 work-log preflight；文档更新后的最新 PR-head gate 应在合并前确认。

## 下一步

PR #350 保持 OPEN，等待 review 和最新 PR-head gate；未经用户明确授权不得合并。后续继续一次只推进一个可独立验证的切片。

## 已知风险

- EPIPE 重试只存在于集成测试连接 helper，重试次数有限；若服务在 TLS 握手时持续关闭连接，测试仍失败。
- 本地没有 Flutter/Dart SDK，验证依赖固定工具链 CI。
- native、KTV recovery、runtime-release、icon 和其他 specialist workflows 未逐项审计。

最后更新：2026-11-05（Asia/Hong_Kong）

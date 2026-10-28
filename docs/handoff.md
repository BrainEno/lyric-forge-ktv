# Handoff

## 目标
Verify a pair of external engineering reviews against the current LyricForge source and preserve only substantiated issues and measurable follow-ups in the development roadmap.

## Git 现场
- Repository: `BrainEno/lyric-forge-ktv`
- Main baseline reviewed: `e8ea44ee4baa3da1709c9f5a665d0c01926e9e99` (`feat: compare ASR preprocessing paths on paired corpus (#205)`)
- Branch: `docs/engineering-risks-roadmap-20261028`
- PR: [#206 docs: record verified engineering risks roadmap](https://github.com/BrainEno/lyric-forge-ktv/pull/206)
- First documentation commit: `0feb3625b40f736009524356bad44855bfa123dd`; follow-up commit repairs the generated-summary spacing and refreshes this handoff.
- Local Dart/Flutter SDK is unavailable in this execution environment; GitHub Actions is the validation path.

## 已改文件
- `docs/engineering_risks_roadmap.md`
- `docs/work_log_index.md`
- `docs/work_log.md`
- `docs/work_log_archive.md`
- `docs/log/entries/2026-10-28-1235-verify-engineering-review-risks.md`
- `docs/handoff.md`

## 本轮实现
- Confirmed the macOS Release entitlement gap: Release lacks `com.apple.security.network.server`, while Debug has it; the current workflow checks only `com.apple.security.network.client`.
- Corrected the claim that ASR has no process/health management: cancellation, stderr capture, CLI process handling, and runtime readiness checks already exist, but the Whisper process wait lacks an explicit operation timeout.
- Classified full-document JSON persistence and the separate playback/capture/monitor audio paths as risks requiring benchmarks or hardware measurements, not proven severe failures.
- Recorded existing Media Hub single-range/206/416/token functionality and prioritized boundary tests, query-token review, and Release smoke testing instead of rewriting working code.

## 检查结果
- Reviewed ASR adapter/orchestration, JSON repositories, Media Hub HTTP/token handling, macOS entitlement plists, and the entitlement-validation workflow.
- Verified the entitlement meaning against Apple's current documentation and Flutter's macOS Release guidance.
- The PR's first Flutter Quality Gate run (`40633713454`) was in progress at the first push; a newer run is expected after the follow-up commit. Check the latest head/run before concluding CI status.
- `dart tool/work_log.dart check`, `flutter analyze`, and `flutter test` were not run locally because Dart/Flutter SDKs are not installed.

## 下一步
Check the latest head of PR #206 and its Flutter Quality Gate, especially the generated work-log preflight. Do not merge on the basis of the earlier head's status. The Release entitlement itself remains a separate code/configuration fix to complete before a macOS Release advertises Media Hub sharing.

## 已知风险
- This PR is documentation-only; it records but does not fix the missing Release server entitlement.
- ASR timeout policy must account for long songs and platform process termination behavior; avoid one universal timeout.
- JSON scaling needs measured cold-load/search/write/memory data before deciding on SQLite migration.
- Audio monitoring delay and long-take drift require physical-device loopback tests; no zero-latency promise is justified.
- No real-song recognition accuracy result was produced by this review.

最后更新：2026-10-28 12:35（Asia/Taipei）

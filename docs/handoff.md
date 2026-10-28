# Handoff

## 目标
Maintain open-source, local-first KTV software with dependable product functionality, audio quality, recovery, security, installation and maintainability.

## Git 现场
- Repository: BrainEno/lyric-forge-ktv
- Main baseline: e2ceb554e3c2e291d602969841d725dd02438e0f
- Branch: fix/macos-release-network-server-entitlement-20261028
- PR: pending creation for the macOS Release Media Hub entitlement fix.
- Scope: Release entitlement + macOS CI enforcement, with work-log and roadmap updates.
- Local Flutter/macOS signing SDKs are unavailable in this execution environment; GitHub Actions is the validation gate.

## 已改文件
- macos/Runner/Release.entitlements
- .github/workflows/macos-network-entitlements-validation.yml
- docs/engineering_risks_roadmap.md
- docs/work_log_index.md
- docs/work_log.md
- docs/work_log_archive.md
- docs/log/entries/2026-10-28-1345-fix-macos-release-network-entitlement.md
- docs/handoff.md

## 本轮实现
- Added `com.apple.security.network.server=true` to macOS Release entitlements to support the Media Hub inbound HTTP listener.
- Updated CI to check both client and server permissions in Debug/Profile and Release source plists and in codesign-extracted Debug/Release app artifacts.
- Updated the verified engineering-risk roadmap and work-log navigation; no change is made to Media Hub authentication/range handling.

## 检查结果
- The source and built-artifact checks are added but still require a successful GitHub Actions run on the final PR head.
- No local Flutter analysis/tests or macOS packaged-app smoke test was run from this environment.
- LAN/Tailscale streaming, health/list/Range behavior and listener shutdown must be verified with the packaged Release app before end-to-end support is claimed.

## 下一步
1. Review the final PR diff and confirm the macOS entitlement workflow and Flutter quality gate pass on the current head.
2. Run packaged Release smoke tests from a second device over LAN and supported Tailscale, then verify stop/dispose closes the listener.
3. Continue the highest-priority JSON persistence delete-before-rename recovery window and fault-injection tests.
4. Harden ASR CLI operation timeout/cancellation cleanup so stalled child processes cannot block the queue indefinitely.

## 已知风险
- Entitlements allow the sandbox to listen but do not independently validate network binding, firewall reachability, authentication, or file streaming.
- No packaged Release device test has yet been executed.
- JSON persistence replacement recovery and ASR process timeout remain separate prioritized engineering tasks.

最后更新：2026-10-28 13:45（Asia/Taipei）

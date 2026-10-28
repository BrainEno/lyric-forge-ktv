# [2026-10-28 13:45] Fix macOS Release Media Hub network entitlement

- Scope: Enable the supported Media Hub listener in sandboxed macOS Release builds and make missing inbound-network permission a CI failure for both source entitlements and built/signed Debug and Release apps.
- Files: `macos/Runner/Release.entitlements`, `.github/workflows/macos-network-entitlements-validation.yml`, `docs/engineering_risks_roadmap.md`, `docs/work_log_index.md`, `docs/work_log.md`, `docs/work_log_archive.md`, `docs/handoff.md`, `docs/log/entries/2026-10-28-1345-fix-macos-release-network-entitlement.md`.
- Validation:
  - Added `com.apple.security.network.server=true` to Release entitlements, matching Debug/Profile and the Media Hub's inbound HTTP listener.
  - Extended the macOS workflow to assert both `network.client` and `network.server` in source plists and in the codesign-extracted Debug/Release app entitlements.
  - GitHub Actions macOS build/signing and Flutter regression jobs are the validation gates; their result is pending on this branch.
- Notes: No local Flutter/macOS signing environment is available here. Packaged Release LAN/Tailscale connection and listener-shutdown smoke tests remain unverified and are not claimed as passing.
- Commit: `fix: enforce macOS Release Media Hub network entitlement`

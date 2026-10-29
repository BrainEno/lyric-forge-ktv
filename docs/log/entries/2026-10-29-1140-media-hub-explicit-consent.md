# [2026-10-29 11:40] Require explicit consent before Media Hub sharing

- Scope: Reduce the security exposure in issue #218 by removing implicit Media Hub startup when the transfer screen opens, requiring explicit consent before starting or replacing an active HTTP session, and displaying a persistent explanation of the plaintext-LAN risk.
- Files: `lib/features/transfer/presentation/screens/desktop_media_transfer_hub_v2_screen.dart`, `test/features/transfer/media_hub_security_consent_contract_test.dart`, `docs/work_log.md`, `docs/work_log_archive.md`, `docs/work_log_index.md`, `docs/handoff.md`, `docs/log/entries/2026-10-29-1140-media-hub-explicit-consent.md`.
- Validation:
  - Added a regression contract test that verifies opening/refreshing the screen cannot start a stopped listener without explicit consent.
  - GitHub Actions Flutter Quality Gate is required on the PR head; local Flutter/Dart SDKs are unavailable in this environment.
- Notes: This is a risk-reduction stage, not a claim that issue #218 is fully resolved. The current Media Hub protocol still uses plain HTTP on ordinary LAN connections. A later protocol-level change must provide authenticated TLS (or an equivalent reviewed end-to-end encryption design) before the issue can be closed.
- Commit: `security: require explicit consent before Media Hub sharing`

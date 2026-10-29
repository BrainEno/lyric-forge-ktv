# Handoff

## 目标
Resolve the critical Media Hub transport risk in issue #218. This branch replaces the former plaintext LAN protocol with fingerprint-pinned HTTPS, keeps sharing off until explicit user consent, and restricts listeners to detected private-LAN/Tailscale IPv4 addresses plus loopback for local playback.

## Git 现场
- Repository: BrainEno/lyric-forge-ktv
- Base: `f711ebe48002089ec110c05703b3c5975bb82e20`
- Branch: `security/explicit-media-hub-consent-20261029`
- PR: https://github.com/BrainEno/lyric-forge-ktv/pull/239
- Current branch head must be checked before further edits.
- Local Flutter/Dart SDKs are unavailable in this environment; use GitHub Actions for validation.

## 已改文件
- `lib/features/transfer/data/services/http_media_hub_service.dart`
- `lib/features/transfer/data/services/http_media_hub_client_service.dart`
- `lib/features/transfer/data/services/media_hub_tls_identity_store.dart`
- `lib/features/transfer/data/services/media_hub_discovery_auth.dart`
- `lib/features/transfer/data/services/udp_media_hub_discovery_service.dart`
- `lib/features/transfer/data/services/media_hub_rebinding_audio_player_service.dart`
- `lib/features/transfer/domain/models/media_hub_connection.dart`
- `lib/features/transfer/domain/models/media_hub_discovery.dart`
- `lib/features/transfer/domain/models/media_hub_session.dart`
- `lib/features/transfer/presentation/screens/desktop_media_transfer_hub_v2_screen.dart`
- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/res/xml/network_security_config.xml`
- Media Hub TLS, pairing/discovery, artwork, upload, and audio playback regression tests
- Work-log entry, active summary, handoff, and index

## Security implementation
- Generate and persist a per-installation self-signed certificate/key pair; pin its SHA-256 DER fingerprint from the QR pairing flow.
- Require HTTPS protocol version 2 and fingerprint matching for Media Hub client requests.
- Bind server listeners only to detected private-LAN/Tailscale IPv4 addresses; retain loopback-only access for local playback, never wildcard bind.
- Require bearer authorization headers; keep session tokens out of audio URLs and route native playback via a loopback proxy that forwards pinned HTTPS with Range/If-Range semantics.
- Disable Android cleartext globally; allow it only for the loopback native-audio proxy.
- Keep sharing stopped by default and require affirmative consent before starting or replacing the active session.
- Update UI wording to describe HTTPS certificate pinning and the actual sharing scope, not the superseded plaintext-HTTP risk.

## 检查结果
- Latest validated commit before the current follow-up edits: Flutter Quality Gate passed, KTV history/recovery validation passed, and Windows Debug native build passed on `3c264855420dd65f31492e2295cd079220f5c4b4`.
- The final head after UI/docs cleanup must trigger and pass the same complete validation again.
- Existing TLS identity, pinned client, upload rejection, discovery recovery, playback Range, and consent contract tests are included; no tests were removed or skipped.
- Do not close #218 or merge until the latest head's complete CI is green.

## 后续工作
1. Re-run the full CI set after the UI wording, contract tests, docs, and code-cleanup commit.
2. Review any new CI failures from exact logs, without weakening tests.
3. Once validation is green, update PR metadata to accurately reflect the TLS fix and close #218 via merge.
4. Continue with remaining open issues in severity order; issue #222 is substantially covered by token removal from playback URLs, while upload resource limits (#224) and CORS/constant-time comparison (#227) remain separate follow-ups.

## 已知边界
- TLS is self-signed and trusted by exact SHA-256 certificate pinning during pairing; legacy protocol-v1 connections must pair again.
- Listener discovery and binding currently target IPv4.
- Physical phone/desktop pairing and real audio playback still need a real pairing and playback smoke test.

最后更新：2026-10-29 16:05（Asia/Taipei）

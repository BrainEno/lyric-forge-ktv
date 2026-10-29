# Handoff

## 目标
Resolve issue #222's remaining Media Hub credential leak: remote artwork URLs must not carry the long-lived session token and protected images must be fetched through the authenticated, certificate-pinned client.

## Git 现场
- Repository: `BrainEno/lyric-forge-ktv`
- Base: `main@0e62beafe36c807b31297454c87311bb465bf8ed`
- Branch: `security/remove-mediahub-token-from-artwork-urls-20261029`
- PR: to be opened after work-log contract and changed-Dart formatting checks.

## 已改文件
- `lib/features/transfer/presentation/screens/remote_catalog_utils.dart` — stop adding `token` and strip legacy token query parameters.
- `lib/features/transfer/presentation/widgets/remote_media_artwork.dart` — use `client.fetchArtwork(track)` and render authenticated bytes using `Image.memory`, not `Image.network`.
- `test/features/transfer/media_hub_security_consent_contract_test.dart` — assert the server refuses query-token auth, artwork URL code strips token, and remote artwork uses authenticated fetch.
- `docs/log/entries/2026-10-29-2050-remove-token-query-artwork.md`, `docs/work_log.md`, `docs/work_log_archive.md`, `docs/work_log_index.md`, `docs/handoff.md`.

## 检查结果
- The HTTP Media Hub server already authorizes through `Authorization: Bearer` and does not read `request.uri.queryParameters['token']`.
- The audio rebinding proxy already removes legacy token query parameters and forwards credentials in the HTTPS Authorization header.
- This patch closes the remaining artwork helper that appended the token and changes the artwork widget to authenticated fetch.
- Final-head Flutter Quality Gate is pending; local Flutter/Dart SDKs are unavailable.

## 下一步
1. Run final-head work-log lint, formatter, analyzer, and the full test suite; fix exact CI findings.
2. Verify the mobile remote catalog artwork and Now Playing artwork regressions through the existing resolver/cache path.
3. Keep #222 open until the fix passes CI and is merged.
4. Continue to remaining high-priority #223 test-distribution issue and then the other audit/refactor issues.

## 已知风险
- The `remoteArtworkUri` metadata field remains for compatibility, but it must contain a credential-free URI only. The current remote playback resolver fetches and caches artwork through the authenticated client and removes this metadata field from the rebound playback item.
- Platform device checks for mobile artwork and system-media notifications remain separate from the automated Flutter tests.

最后更新：2026-10-29 20:50（Asia/Taipei）

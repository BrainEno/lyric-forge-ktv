# Handoff

## 目标
Address the remaining timing-attack surface in issue #222 by using a shared no-content-early-exit comparison for Media Hub Bearer tokens and discovery proofs, and add regression coverage that query-string tokens do not authenticate uploads.

## Git 现场
- Repository: `BrainEno/lyric-forge-ktv`
- Base: `main@72f33d4ce2d3101d61b595ef3d15e3e860fcd7a9`
- Branch: `security/constant-time-media-hub-tokens-20261029`
- PR: https://github.com/BrainEno/lyric-forge-ktv/pull/245 (draft pending final-head CI).
- Existing baseline: PR #239 already enforces Bearer headers and removes `token` query parameters from proxy/rebase player URLs.

## 已改文件
- `lib/features/transfer/data/services/http_media_hub_service.dart`
- `lib/features/transfer/data/services/media_hub_discovery_auth.dart`
- `test/features/transfer/media_hub_discovery_auth_test.dart`
- `test/features/transfer/http_media_hub_upload_test.dart`
- `test/features/transfer/media_hub_security_consent_contract_test.dart`
- `docs/log/entries/2026-10-29-1738-constant-time-media-hub-token-comparison.md`
- `docs/work_log.md`, `docs/work_log_archive.md`, `docs/work_log_index.md`, `docs/handoff.md`

## 检查结果
- HTTP Bearer authorization now calls `mediaHubConstantTimeEquals`; comparison accumulates code-unit XOR differences and does not return early based on content or length.
- `mediaHubDiscoveryProofMatches` now delegates to the same comparison primitive.
- Unit coverage checks exact matches, first/middle/last mismatches, empty input, unequal lengths, and discovery proofs.
- Upload integration coverage supplies the valid session token only as a URL query parameter and expects HTTP 401; the transport contract verifies proxy/rebase code removes tokens from URL queries.
- Local Dart/Flutter SDKs are unavailable; final-head Flutter Quality Gate must pass before merge.

## 下一步
1. Open the dedicated PR against `main` and inspect the diff.
2. Check work-log preflight, formatter, analyzer, and full tests on the final head.
3. Keep #222 open until the PR is merged; continue to #227 (CORS origin policy) only after this validation.

## 已知风险
- Dart VM execution does not promise formal machine-code constant-time behavior. This change removes explicit early exits on comparison content and length from the application logic.
- The query-token denial test uses the existing pinned-HTTPS local server integration harness; physical phone/desktop pairing remains a separate device-level smoke test.
- CORS policy is intentionally left to issue #227 and is not changed in this PR.

最后更新：2026-10-29 17:42（Asia/Taipei）

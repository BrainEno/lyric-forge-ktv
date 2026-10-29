# Handoff

## 目标
Address issue #227's wildcard CORS finding. Media Hub is used by native Flutter clients over fingerprint-pinned HTTPS and does not need browser-origin access, so do not grant browser CORS permissions.

## Git 现场
- Repository: `BrainEno/lyric-forge-ktv`
- Base: `main@0e62beafe36c807b31297454c87311bb465bf8ed`
- Branch: `security/media-hub-cors-origin-policy-20261029`
- PR: to be opened after final review of the security contract tests.
- The constant-time Bearer comparison portion is handled separately by PR #245.

## 已改文件
- `lib/features/transfer/data/services/http_media_hub_service.dart`
- `test/features/transfer/http_media_hub_upload_test.dart`
- `test/features/transfer/media_hub_security_consent_contract_test.dart`
- `docs/log/entries/2026-10-29-1750-disable-wildcard-cors-media-hub.md`
- `docs/work_log.md`, `docs/work_log_archive.md`, `docs/work_log_index.md`, `docs/handoff.md`

## 检查结果
- Removed `Access-Control-Allow-Origin: *`, `Access-Control-Allow-Headers`, and `Access-Control-Allow-Methods` from all Media Hub responses.
- Browser `OPTIONS` preflights now return HTTP 405 and emit no CORS allow headers.
- Added pinned-HTTPS integration coverage for an attacker Origin and Authorization preflight; added source contract assertions to prevent reintroduction of wildcard CORS.
- Local Flutter/Dart SDKs are unavailable; final-head Flutter Quality Gate must pass before merge.

## 下一步
1. Open the dedicated PR and verify the final-head work-log, format, analyzer, and complete test suite.
2. Keep #227 open until the CORS fix is merged; token comparison is handled in PR #245.
3. Continue with #234's `.part` reservation race before addressing lower-risk audit/refactor issues.

## 已知风险
- Browser-based clients are intentionally unsupported by the Media Hub API. If a web client is introduced in the future, define a narrow explicit origin policy rather than restoring wildcard CORS.
- Absence of CORS is a browser response-reading restriction, not authentication; bearer authorization and TLS certificate pinning remain required.
- This PR doesn't change rate limits or the `.part` file reservation race tracked in #234.

最后更新：2026-10-29 17:50（Asia/Taipei）

# Handoff

## 目标
Continue the audit-driven issue queue in risk order, one issue per branch/PR. Current active item is #217: make managed FFmpeg installs reproducible and fail closed on integrity mismatch.

## Git 现场
- Repository: BrainEno/lyric-forge-ktv
- Main baseline: `e975aa4349317e82accdd8253fbf7d76cb42fcd1`
- Branch: `fix/pin-verify-ffmpeg-20261028`
- PR compare view: https://github.com/BrainEno/lyric-forge-ktv/compare/main...fix/pin-verify-ffmpeg-20261028
- Local Flutter/Dart SDKs are unavailable in this environment; use GitHub Actions for validation.
- Code/test head `dc53fca810663679fd2bb6e56e3ef4ecdd9b518e` has all six relevant workflows green.

## 已改文件
- `lib/features/transcription/data/services/managed_asr_runtime_manager.dart`
- `lib/features/transcription/data/services/ffmpeg_runtime_release.dart`
- `lib/features/transcription/data/services/runtime_sha256.dart`
- `test/runtime_integrity_install_contract_test.dart`
- `test/ffmpeg_runtime_release_test.dart`
- `test/runtime_sha256_test.dart`
- `docs/engineering_risks_roadmap.md`
- `docs/log/entries/2026-10-28-2215-pin-and-verify-managed-ffmpeg.md`
- `docs/work_log.md`
- `docs/work_log_archive.md`
- `docs/work_log_index.md`
- `docs/handoff.md`

## 检查结果
- Code/test head `dc53fca810663679fd2bb6e56e3ef4ecdd9b518e`: all six relevant workflows passed. Flutter Quality Gate and the three relevant full-regression workflows each reported 784 tests passed; ASR client checks passed.
- Initial PR checks exposed two root causes: Dart 3.13 formatting drift in the touched legacy manager file, and a contract test whose source-wide index lookup matched the Qwen extraction before the FFmpeg extraction. Both are repaired; no check was bypassed or weakened.
- Local Dart/Flutter commands were not run because SDKs are unavailable in this environment.

## 下一步
1. Finish the documentation-only validation refresh for PR #237 and keep the issue open until review/merge.
2. Address CI issue #225 in its own PR: unify workflow SDK setup, stop duplicate full-suite runs in specialist jobs, and remove stale branch-specific triggers while retaining the universal full-suite gate.
3. Then address #218 (Media Hub cleartext HTTP/security scope) in its own PR.

## 已知风险
- The archive pins are reproducible, but they do not replace end-to-end execution on each supported OS/architecture.
- Real download/proxy behavior and directory-swap rollback still require platform verification.

最后更新：2026-10-28 22:15（Asia/Taipei）

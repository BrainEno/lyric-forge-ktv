# Handoff

## 目标
Resolve issue #216 by enforcing one Flutter/Dart toolchain across local quality gates, platform build scripts, and CI so the bundled `dart_style` version cannot silently differ between contributors.

## Git 现场
- Repository: `BrainEno/lyric-forge-ktv`
- Base: `main@0e62beafe36c807b31297454c87311bb465bf8ed`
- Branch: `build/enforce-pinned-flutter-sdk-locally-20261029`
- PR: to be opened after final diff review and a green final-head quality gate.
- Active version source: `.fvmrc` (`flutter: 3.47.7`).

## 已改文件
- `scripts/check_flutter_sdk.sh`
- `scripts/check_flutter_sdk.ps1`
- `scripts/quality_gate.sh`, `scripts/quality_gate.ps1`
- `scripts/ios_build.sh`, `scripts/build_android_apk.ps1`
- `.github/actions/setup-flutter/action.yml`
- `test/ci_workflow_contract_test.dart`
- `docs/development-environment.md`
- `docs/log/entries/2026-10-29-1925-enforce-pinned-flutter-sdk-local-gates.md`
- `docs/work_log.md`, `docs/work_log_archive.md`, `docs/work_log_index.md`, `docs/handoff.md`

## 检查结果
- The shared CI action installs the Flutter version read from `.fvmrc`, then runs the same SDK check as local entry points.
- The SDK check compares Flutter `frameworkVersion` to `.fvmrc` and compares `dart --version` to Flutter's `dartSdkVersion`; it fails fast on either mismatch.
- Shell and PowerShell quality gates check the toolchain before work-log lint/dependency resolution/analyze/tests. iOS prep and Android APK build scripts check before modifying/building outputs.
- Added CI contract tests to ensure the shared action and local scripts preserve these calls. Final-head Flutter Quality Gate must pass; local Dart/Flutter SDKs are unavailable in this environment.

## 下一步
1. Verify work-log lint, formatter, analyzer, and full test suite on the final PR head.
2. Inspect any Windows PowerShell errors if CI reports them; don't relax the version comparisons.
3. Keep #216 open until the PR is merged and the same check is exercised on Windows/macOS/Ubuntu runners.
4. Continue to #215 README cleanup and then the higher test-distribution (#223) / architecture audit issues by impact.

## 已知风险
- The check validates the `dart` executable resolved on PATH, which intentionally rejects setups where Flutter and Dart come from different SDK directories even if both are individually functional.
- `.metadata` keeps Flutter project creation/migration provenance; it is not updated manually or treated as the active SDK selector. `.fvmrc` is authoritative.
- The new check requires `sed`/`head` on Bash environments and PowerShell's built-in JSON support on Windows; GitHub runners and normal Flutter development environments supply these.

最后更新：2026-10-29 19:25（Asia/Taipei）

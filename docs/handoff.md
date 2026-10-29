# Handoff

## 目标
Resolve issue #219 by replacing Flutter template application identities with a stable repository-owned reverse-DNS identifier and preventing regressions in CI.

## Git 现场
- Repository: `BrainEno/lyric-forge-ktv`
- Base: `main@0e62beafe36c807b31297454c87311bb465bf8ed`
- Branch: `fix/platform-app-identifiers-20261029`
- PR: https://github.com/BrainEno/lyric-forge-ktv/pull/243.
- Canonical application identifier: `io.github.braineno.lyricforge`

## 已改文件
- `android/app/build.gradle.kts`
- `android/app/src/main/kotlin/io/github/braineno/lyricforge/MainActivity.kt` (moved from the template package path)
- `ios/Runner.xcodeproj/project.pbxproj`
- `macos/Runner.xcodeproj/project.pbxproj`
- `macos/Runner/Configs/AppInfo.xcconfig`
- `linux/CMakeLists.txt`
- `windows/runner/Runner.rc`
- `scripts/check_app_identifiers.sh`
- `.github/workflows/flutter-quality.yml`
- `docs/log/entries/2026-10-29-1708-remove-template-app-identifiers.md`
- `docs/work_log.md`
- `docs/work_log_archive.md`
- `docs/work_log_index.md`
- `docs/handoff.md`

## 检查结果
- Repository file checks confirm the Android namespace, application ID, and Kotlin package match; iOS/macOS app and test bundle identifiers are aligned; Linux GTK identity is aligned; Windows metadata no longer uses the template owner string.
- Added a pre-Flutter CI script that verifies all expected identifiers, fails on any `com.example` in platform identity files, and checks that the old Android activity path is absent.
- Run final-head GitHub Actions, Android build, and applicable desktop build workflows before considering the issue resolved. No local Flutter SDK is available in this environment.

## 下一步
1. Open the dedicated PR and review final diff for all platform identity substitutions.
2. Verify the new CI contract and Android/desktop build workflows on the final PR head.
3. Keep issue #219 open until the PR is merged and builds are confirmed.

## 风险
- Changing an application identifier after publication creates a distinct app identity. The repository issue states that no user-facing app build has been distributed, so this early change avoids future rename/data-migration cost.
- Windows `Runner.rc` supplies company/copyright version-resource metadata rather than a package bundle ID; no Store/MSIX package identity is currently defined here.

最后更新：2026-10-29 17:09（Asia/Taipei）

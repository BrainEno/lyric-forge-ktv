# Handoff

## 目标
Stabilize the repository CI architecture under issue #225, then continue with the next independently prioritized issue. The current branch unifies Flutter SDK selection and removes duplicate full-suite CI work without weakening the universal test gate.

## Git 现场
- Repository: BrainEno/lyric-forge-ktv
- Main baseline: `ee42fffec5edf0d86a0a258c97b23b573090b6ba` (includes merged PR #237)
- Branch: `ci/unify-flutter-workflows-20261028`
- Conflict resolution retains PR #237's managed FFmpeg/runtime integrity changes while layering PR #238's CI changes on the current main tree.
- Compare view: https://github.com/BrainEno/lyric-forge-ktv/compare/main...ci/unify-flutter-workflows-20261028
- Local Flutter/Dart SDKs are unavailable in this environment; use GitHub Actions for validation.

## 已改文件
- `.fvmrc`
- `.github/actions/setup-flutter/action.yml`
- `.github/workflows/*.yml` (centralized SDK setup, focused tests, concurrency, dead KTV triggers)
- `test/ci_workflow_contract_test.dart`
- `docs/log/entries/2026-10-28-2310-unify-flutter-ci-workflows.md`
- `docs/work_log.md`
- `docs/work_log_archive.md`
- `docs/work_log_index.md`
- `docs/handoff.md`

## 检查结果
- The changes preserve the universal quality gate as the only workflow entrypoint responsible for the full Flutter suite.
- Added CI contract tests that inspect every workflow for shared SDK setup and for accidental duplicate full-suite commands; they also verify the KTV recovery/WAV focused-test ownership and absence of dead branch-only triggers.
- Earlier validation on the pre-conflict head passed Flutter Quality Gate and most specialist workflows; the latest merge commit must be revalidated because its tree now includes current main plus the conflict-resolved CI changes. No final-head green result is claimed until that run completes.
- Local Dart/Flutter commands were not run because the SDKs are unavailable in this environment.

## 下一步
1. Inspect the new merge commit's CI runs, including Ubuntu full-suite, Windows native build, macOS native builds, and managed ASR runtime compilation.
2. Fix actual test/toolchain/platform failures; do not weaken assertions or skip native builds.
3. After CI architecture is green, separately address issue #220 by making dependency-lock resolution explicit and detecting tool-generated tracked-file changes.

## 已知风险
- Unifying to the SDK used by the universal quality gate can expose native plugin/build incompatibilities previously hidden by specialist workflows pinned to older Flutter versions; platform jobs must be allowed to reveal these, not skipped.
- The repository's lockfile/analysis-options reproducibility problem in issue #220 remains a separate follow-up and is not considered resolved by changing the SDK pin.

最后更新：2026-10-28 23:53（Asia/Taipei）

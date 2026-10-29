# Handoff

## 目标
Resolve the companion slice of issue #215: add clear contribution guidance and GitHub intake/review templates without expanding the README/package metadata PR.

## Git 现场
- Repository: `BrainEno/lyric-forge-ktv`
- Base: `main@0e62beafe36c807b31297454c87311bb465bf8ed`
- Branch: `docs/contribution-and-github-templates-20261029`
- PR: to be opened as a draft companion to https://github.com/BrainEno/lyric-forge-ktv/pull/250.
- Ordering: do not merge this slice before PR #250; both update work-log navigation and should be rebased after #250 lands.

## 已改文件
- `CONTRIBUTING.md` — setup, validation, architecture, privacy, and work-log protocol.
- `.github/ISSUE_TEMPLATE/bug_report.yml` — reproducible steps, platform, version, relevant environment, sanitized logs.
- `.github/ISSUE_TEMPLATE/feature_request.yml` — problem, proposal, target platform, alternatives, local-first fit.
- `.github/PULL_REQUEST_TEMPLATE.md` — summary, linked issue, checks, data/privacy compatibility, screenshots.
- `docs/log/entries/2026-10-29-2045-add-contribution-and-github-templates.md`, `docs/work_log.md`, `docs/work_log_archive.md`, `docs/handoff.md`.

## 检查结果
- Forms avoid asking users to upload copyrighted audio, private data, secrets, model weights, or unredacted paths.
- PR template asks contributors to report commands actually run and explain any skipped platform/device checks.
- Final-head Flutter Quality Gate remains pending; local Flutter/Dart SDKs are unavailable.

## 下一步
1. Open the companion PR as Draft and let its pull-request quality gate run against main.
2. After PR #250 merges, rebase this branch onto the new main and regenerate work-log files; rerun CI on the rebased final head.
3. Only mark this PR ready after the rebased quality gate is green. Keep #215 open until both slices are merged.

## 已知风险
- This PR intentionally overlaps the generated work-log files with PR #250; it must be rebased before merge to prevent stale summaries or a missing entry link.
- GitHub form rendering is verified by GitHub after the PR is opened; this environment does not run GitHub's form schema validator locally.

最后更新：2026-10-29 20:45（Asia/Taipei）

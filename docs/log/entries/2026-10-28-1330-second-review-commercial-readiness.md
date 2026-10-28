# [2026-10-28 13:30] Incorporate second engineering review into readiness roadmap

- Scope: Verify the second static commercial-readiness review against fixed source commit e8ea44ee4baa3da1709c9f5a665d0c01926e9e99, distinguish confirmed implementation gaps from legal/performance validation questions, and prioritize release-blocking follow-ups.
- Files: docs/engineering_risks_roadmap.md, docs/work_log_index.md, docs/work_log.md, docs/work_log_archive.md, docs/log/entries/2026-10-28-1330-second-review-commercial-readiness.md, docs/handoff.md.
- Validation:
  - Inspected the fixed source for JSON replacement order, Qwen runtime build/provenance, managed FFmpeg installation, Media Hub listener/upload/token handling, KTV mix filters, Android signing, runtime build targets, product requirements and packaging workflows.
  - Checked the exact pinned Qwen source tree and confirmed no LICENSE/COPYING/NOTICE path is present at the pinned revision; the build workflow currently ignores failure to copy the source licence file.
  - Verified current public licence references for flutter_soloud/SoLoud and rejected the report's unsupported GPL classification.
  - Confirmed only runtime ZIPs, not an app installer, are attached to the reviewed GitHub Releases snapshot.
  - Local dart tool/work_log.dart check, flutter analyze, and flutter test were not run because Dart/Flutter SDKs are unavailable in this execution environment; the PR quality gate remains required.
- Notes: Added P0/P1 data-integrity, runtime-license, upload-resource, FFmpeg provenance, separation-scope, distribution/signing, quality-corpus and mix-peak tasks. No production code or release artifact was changed. The report's Demucs/SoLoud/CI-count claims were qualified rather than adopted blindly.
- Commit: `docs: extend engineering roadmap with release blockers`

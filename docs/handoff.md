# Handoff

## 目标
Convert the second external review into a source-verified commercial-readiness roadmap, without importing inaccurate claims or making unverified performance/legal assumptions.

## Git 现场
- Repository: BrainEno/lyric-forge-ktv
- Source baseline for findings: e8ea44ee4baa3da1709c9f5a665d0c01926e9e99
- Main baseline for this documentation change: 5d7a6ff2179765399f5ed66fb1d01c9a6852076a
- Branch: docs/second-review-commercial-readiness-20261028
- The previously merged PR #206 established docs/engineering_risks_roadmap.md; this task extends that roadmap with the second review's additional findings.
- Local Dart/Flutter SDK is unavailable in this execution environment; PR CI is required.

## 已改文件
- docs/engineering_risks_roadmap.md
- docs/work_log_index.md
- docs/work_log.md
- docs/work_log_archive.md
- docs/log/entries/2026-10-28-1330-second-review-commercial-readiness.md
- docs/handoff.md

## 本轮实现
- Corrected the earlier over-broad statement about temp-file writes: at least ten JSON stores write a temporary file, delete the canonical file, then rename. The old file is therefore not protected throughout the replacement sequence.
- Added a release gate for the pinned Qwen Rust runtime's missing upstream licence file; the workflow's licence copy step currently ignores failure.
- Added Media Hub request limits, safe temporary upload names/concurrency, token and plaintext-LAN threat-model checks.
- Added FFmpeg latest-artifact pin/hash verification, desktop separation-vs-PRD closure, application artifact packaging and Android production signing gates.
- Added real-song ASR baseline requirements and rendered-mix peak measurements.
- Rejected unsupported claims: flutter_soloud/SoLoud is not established as GPL by the checked licence references; workflow count alone does not justify removal/consolidation; existing recovery/runtime tests are real and should be extended, not dismissed.

## 检查结果
- Source-level findings were cross-checked at the fixed commit; runtime release assets and workflow targets were inspected.
- No application code was changed.
- dart tool/work_log.dart check, flutter analyze, and flutter test were not run locally because Dart/Flutter SDKs are unavailable. Wait for the latest PR Quality Gate before treating documentation lint as passed.

## 下一步
Check the latest PR CI result and review the roadmap diff. Implementation should start with (1) Qwen runtime licence/redistribution decision, (2) delete-before-rename data safety and recovery, then (3) bounded upload handling and FFmpeg artifact integrity. These items are recorded, not fixed, in this documentation-only PR.

## 已知风险
- No lawyer reviewed the Qwen runtime licence; this is a rights/provenance blocker requiring permission confirmation, not a legal verdict.
- No crash-injection, malicious upload, real-song, hardware compatibility, or actual mix peak test was executed in this documentation task.
- Demucs weight licensing is not inferred from its code licence; no separator model has been integrated here.
- Existing main source still has the observed gaps until follow-up implementation PRs merge.

最后更新：2026-10-28 13:30（Asia/Taipei）

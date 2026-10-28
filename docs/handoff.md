# Handoff

## 目标
Maintain a source-verified, prioritized engineering roadmap for open-source, local-first KTV software. “Commercial-grade” means mature functionality, reliability, audio quality, installation/upgrade behavior, and maintainability; it does not assume monetization or a commercial distribution model.

## Git 现场
- Repository: BrainEno/lyric-forge-ktv
- Source baseline for review findings: e8ea44ee4baa3da1709c9f5a665d0c01926e9e99
- Main baseline before this documentation series: 5d7a6ff2179765399f5ed66fb1d01c9a6852076a
- Branch: docs/second-review-commercial-readiness-20261028
- PR: [#207 docs: prioritize open-source product quality roadmap](https://github.com/BrainEno/lyric-forge-ktv/pull/207)
- Scope is documentation only; application code and runtime binaries are unchanged.
- Previous CI attempts exposed work-log summary drift and are now corrected. The latest quality-gate status must be checked against the final PR head.
- Local Dart/Flutter SDKs are unavailable in this execution environment; GitHub Actions is the validation gate.

## 已改文件
- docs/engineering_risks_roadmap.md
- docs/work_log_index.md
- docs/work_log.md
- docs/work_log_archive.md
- docs/log/entries/2026-10-28-1339-reframe-product-quality-roadmap.md
- docs/handoff.md

## 本轮实现
- Reframed the roadmap from “commercial readiness” to open-source product quality and install/upgrade maturity.
- Demoted the Qwen runtime's missing upstream notice from a P0 commercial-redistribution blocker to a narrowly scoped provenance/notice task for any future bundled artifact. It does not block local testing, prototyping, or unrelated implementation work.
- Kept actual product/reliability risks: JSON replacement failure window, macOS Media Hub Release entitlement, ASR process timeouts, upload limits and safe temporary files, FFmpeg integrity, vocal/accompaniment separation, real-song evaluation, mix peak behavior, app packaging, and hardware support matrix.
- Removed generic legal-review/commercial-use approval language. Keep only the third-party attribution/redistribution requirements that apply to artifacts actually included in an open-source bundle.

## 检查结果
- Documentation and navigation changes only; no app source or model/runtime binary modified.
- The work-log summary and archive links were updated for the new entry and the shifted active/archive boundary.
- Dart/Flutter checks were not run locally because the SDKs are unavailable; verify the final GitHub Actions run before merging.

## 下一步
1. Check the final PR CI and review the resulting diff.
2. Start implementation with the JSON delete-before-rename recovery window and fault-injection tests, alongside the ASR stuck-process timeout contract.
3. Continue Media Hub upload resource limits, FFmpeg hash pinning, and real-song/mix-quality evaluation.
4. Prototype and measure desktop vocal/accompaniment separation locally; check redistribution terms only when choosing a model/runtime for bundling, not as a reason to delay local experiments.
5. Complete actual application packaging and stable install/upgrade behavior for the platforms that are genuinely tested.

## 已知风险
- The reviewed Qwen Rust source revision has no LICENSE/COPYING/NOTICE path, and the current build workflow suppresses failure to copy licence files. This matters if that specific runtime is redistributed as a bundled artifact; it is not a monetization or general development gate. Select a clear-provenance bundle or make the distribution behavior explicit before publishing it.
- No crash-injection, malicious-upload, real-song, hardware compatibility, or actual mix-peak test was executed in this documentation task.
- Existing main source still has the observed engineering gaps until follow-up implementation PRs merge.

最后更新：2026-10-28 13:39（Asia/Taipei）

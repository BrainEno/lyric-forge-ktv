# [2026-10-23 09:20] Reject malformed ASR timing evidence

- Scope: Harden the secondary-ASR retiming planner so invalid intervals and out-of-order timestamps reject the complete evidence set instead of allowing a partial, potentially misleading match. Keep confidence validation and surface a clear review reason.
- Files: lib/features/lyrics/domain/proofreading/asr_retiming_planner.dart, test/features/lyrics/domain/proofreading/asr_retiming_planner_test.dart, lib/features/lyrics/presentation/widgets/reference_proofread_timing_review_dialog.dart, this entry.
- Validation: Added regression coverage for zero-duration intervals and descending timestamps, plus UI reason mapping. Full analyzer/tests and work-log validation are delegated to the PR GitHub Actions quality gate; this environment has no local Flutter/Dart runtime.
- Notes: This is intentionally conservative: the planner does not attempt to repair timing evidence or infer timestamps. It rejects malformed source evidence and leaves the draft unchanged.
- Commit: Reject malformed ASR timing evidence

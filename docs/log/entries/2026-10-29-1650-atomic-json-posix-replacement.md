# [2026-10-29 16:50] Atomically replace JSON stores on POSIX

- Scope: Address the atomic-replacement and fault-injection portion of issue #221. POSIX writes now rename the validated temporary JSON directly over the canonical path, avoiding an explicit delete/rename gap; Windows retains the backed-up delete/rename fallback. Recovery uses the same platform-aware replacement strategy.
- Files: `lib/core/persistence/atomic_json_file.dart`, `test/core/persistence/atomic_json_file_test.dart`, `docs/work_log.md`, `docs/work_log_archive.md`, `docs/work_log_index.md`, `docs/handoff.md`, and this entry.
- Validation: GitHub Actions Flutter Quality Gate passed on commit `78e6ba208e3b9f1c8585cc6659b19a3458c8970c` (work-log preflight, formatting, analysis, full tests). The final documentation refresh must be rechecked on its new PR head. Windows-specific runtime validation remains necessary.
- Notes: The cross-platform Windows fallback still relies on backup-based recovery across the delete/rename gap. Adding schemaVersion fields to all participating stores is intentionally not bundled into this change; keep issue #221 open until that migration contract is separately designed and validated.
- Commit: `fix: replace atomic JSON stores without POSIX delete window`

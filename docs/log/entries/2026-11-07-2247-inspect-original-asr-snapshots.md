# [2026-11-07 22:47] Inspect verified original ASR snapshots

- Scope: Enable read-only inspection of verified original dual-ASR snapshots when a fused or edited draft no longer matches the primary transcript.
- Files: Independent snapshot comparison, project evidence model and loader, editor and snapshot dialog, focused domain/data/widget tests, handoff and log navigation.
- Validation:
  - dart format changed Dart files in Actions 43177242146 => formatted; patch applied locally.
  - flutter analyze --no-fatal-infos in Actions 43177242146 => no errors or warnings; info diagnostics remain.
  - Focused snapshot, loader, dialog and editor tests in Actions 43177242146 => 105 passed.
- Notes: Comparison is read-only and restricted to original single-input transcripts; ambiguous overlaps never count as agreement. Audio hashes and revisions are point-in-time checks. Chunk evidence, real recordings and native accessibility remain unverified; #319 stays open.
- Commit: `Document snapshot inspection`

# [2026-11-07 22:46] Audition verified reference alignment timing

- Scope: Enable bounded, explicit listening of reference ForcedAligner times on the verified current audio source before adoption.
- Files: Reference audition planner and coordinator, line audition controller, review dialog and editor, domain/controller/widget/editor tests, handoff and work log index.
- Validation:
  - dart format changed Dart files in Actions 43170164156 => formatted; patch applied locally.
  - flutter analyze --no-pub --no-fatal-infos lib test tool in Actions 43170164156 => no errors or warnings; info diagnostics remain.
  - Focused planner, controller, widget, editor and architecture tests in Actions 43170164156 => 145 passed.
- Notes: Audio and player checks are point-in-time, not locks; pending seeks cannot be cancelled. Real recordings and native accessibility remain unverified; #319 stays open.
- Commit: `Document reference timing audition`

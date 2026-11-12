# [2026-11-07 22:45] Apply reference alignment timing by explicit row choice

- Scope: Allow independently selected reference ForcedAligner timing with guarded composition, provenance and undo.
- Files: V2 composer, timing and audio guards, editor review and assembly, timeline validation, domain and widget tests, work log index and handoff.
- Validation:
  - dart format on changed Dart files via Actions 43165097913 => formatted; patch applied locally.
  - flutter analyze --no-fatal-infos via Actions 43165097913 => no errors or warnings; info diagnostics remain.
  - Focused domain, audio guard, editor, widget and timeline tests via Actions 43165097913 => 379 passed.
- Notes: Audio hashes and revisions are point-in-time checks, not locks or accuracy guarantees. Real recordings and native assistive technology are unverified; #319 remains open.
- Commit: `Document reference timing review`

# [2026-11-07 20:58] Route automatic proofreading evidence transparently

- Scope: Enable optional secondary ASR and ForcedAligner evidence for automatic V2 strategy and explain which evidence was not used (partial #319).
- Files: V2 options and review dialogs, typed explanations, assembler and use case, domain and widget tests, product follow-up and work-log navigation.
- Validation:
  - dart format changed Dart files with pinned SDK => passed in Actions 43065960949.
  - flutter analyze --no-pub --no-fatal-infos lib test tool => passed in Actions 43065960949.
  - flutter test --no-pub targeted evidence matrix, V2 editor, options, review accessibility and architecture contracts => passed in Actions 43065960949.
- Notes: #319 remains open: automatic Whisper snapshot loading, chunk evidence and reference-first ForcedAligner are not implemented. Evidence text is validated before strategy selection; real audio, native aligner, devices and screen readers were not tested.
- Commit: `Route automatic proofreading evidence transparently`

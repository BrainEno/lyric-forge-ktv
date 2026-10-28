# [2026-10-26 16:35] Add repeatable ForcedAligner quality evaluation

- Scope: Add an offline, repeatable benchmark for comparing manually reviewed token intervals against captured ForcedAligner output across languages.
- Files: tool/forced_alignment_eval.dart, test/tool/forced_alignment_eval_test.dart, docs/high_quality_asr.md, docs/handoff.md, docs/work_log.md, docs/work_log_archive.md, docs/work_log_index.md, this entry.
- Validation:
  - `flutter test test/tool/forced_alignment_eval_test.dart` => added regression coverage; execution pending remote CI because no local Flutter SDK is available.
  - `dart format tool/forced_alignment_eval.dart test/tool/forced_alignment_eval_test.dart` => not run locally; remote quality gate must check formatting.
  - `flutter analyze --no-pub` and `dart tool/work_log.dart check` => not run locally; must be checked by GitHub Actions.
- Notes: The tool requires manually checked reference times and actual runtime spans; it contains no fabricated audio benchmark. It measures text recall/precision and absolute boundary errors without changing timestamps. Real Chinese/English/Japanese accuracy remains unverified.
- Commit: `Add repeatable ForcedAligner quality evaluation`

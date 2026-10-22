# Handoff

## Goal
T5 phase 4: suggest reference lyric text for matched ASR rows only; never apply text/timestamps or insert missing lines.

## Git snapshot
- Base `main`: `f6f5cdfd4d42b70dfa0a66dda01844e3311579d7`; branch `feat/lyric-proofreading-t5-reference-suggestions-20261022`; Draft PR #145.
- PR #143 is merged; PR #144 remains Draft to port repetition code missing from main because #142 merged into the old #141 feature branch.
- This environment only has GitHub API; local status/diff/log and Dart/Flutter tools are unavailable.

## Changed files
- `lib/features/lyrics/domain/proofreading/asr_reference_correction_suggester.dart`: sanitizes reference headers, maps original indices, and emits text-only suggestions with alignment evidence/reason codes.
- `test/features/lyrics/domain/proofreading/asr_reference_correction_suggester_test.dart`: typo, low-confidence, protected/identical rows, source-index mapping, missing references, import warnings and immutability.
- Updated proofreading plan, work index and this handoff.

## Checks
- Static review: no draft mutation, no timestamp copy, no auto-insertion; each suggestion requires re-timing.
- Not run: `dart format`, targeted Flutter test, `flutter analyze --no-pub`, lyric regression tests or `dart tool/work_log.dart check`; no CI result.
- No immutable work-log entry; generated `docs/work_log.md` was not hand-edited.

## Next step
Run the commands in PR #145 locally. If they pass, mark it ready for review; verify and merge PR #144 separately so the repetition analyzer lands on main.

## Risks
Existing row alignment does not re-segment lyrics or provide token timing. Low-confidence, ambiguous, structural and reference-import-warning cases need manual review; a text proposal must not be applied until safe re-timing exists.

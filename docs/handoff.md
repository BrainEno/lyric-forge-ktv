# Handoff

## Goal
T5 phase 5: propose timing for changed lyric text only when nearby secondary-ASR timing evidence exactly matches the proposed text.

## Git snapshot
- Base `main`: current branch point; branch `feat/lyric-proofreading-t5-retiming-v2-20261022`; Draft PR #146.
- PRs #143–#145 are reported merged. PR #144 ports repetition code that #142 merged only into the old #141 feature branch.
- This environment only has GitHub API; local status/diff/log and Dart/Flutter tools are unavailable.

## Changed files
- `lib/features/lyrics/domain/proofreading/asr_retiming_planner.dart`: derives candidate time intervals only from exact nearby secondary-ASR text/timing evidence; split phrases allowed, no text-length extrapolation.
- `test/features/lyrics/domain/proofreading/asr_retiming_planner_test.dart`: exact/split matches, missing/ambiguous evidence, low confidence, neighbor/audio bounds and protected/unchanged rows.
- Updated proofreading plan, work index and this handoff.

## Checks
- Static review only: planner does not mutate the draft or infer time from character count; non-unique/low-confidence/out-of-bounds intervals are not ready.
- Not run: `dart format`, targeted Flutter test, `flutter analyze --no-pub`, lyric regression tests or `dart tool/work_log.dart check`; no CI result.
- No immutable work-log entry; generated `docs/work_log.md` was not hand-edited.

## Next step
Run the commands in PR #145 locally. If they pass, mark it ready for review; verify and merge PR #144 separately so the repetition analyzer lands on main.

## Risks
Secondary-ASR timestamps are a proxy, not forced alignment. Exact text match is not phoneme-level proof; no unique confident in-bounds interval means the planner refuses to mark it ready.

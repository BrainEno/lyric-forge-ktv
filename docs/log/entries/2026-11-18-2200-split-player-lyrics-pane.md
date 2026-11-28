# [2026-11-18 22:00] Split the player lyrics pane

- Scope: round 56, move player lyric presentation out of the player screen (D-076).
  - `player_screen.dart`: 1138 → 686 lines; retains project loading/actions, playback session, KTV entry and transport composition.
  - `widgets/player_lyrics_pane.dart`: the lyric pane, no-lyrics state, scrolling synchronized lyrics, KTV focus lyrics and the time formatter.
  - The screen supplies the same lyric data and callbacks through `PlayerLyricsPane`; the extracted widgets do not import the screen.
- Files:
  - New: `lib/features/player/presentation/widgets/player_lyrics_pane.dart` and this entry.
  - Changed: `lib/features/player/presentation/screens/player_screen.dart`, `docs/decisions.md`, `docs/handoff.md`, `docs/work_log.md`, `docs/work_log_archive.md`.
- Validation:
  - `git diff --check` => passed.
  - PR #521 final head `9c206ce`: format check, work-log preflight, analysis, full test suite, KTV history/recovery and KTV take-lock workflows => passed.
  - The first CI runs caught missing imports after moving the lyric widgets; the required model/API imports were restored or relocated, and the final head passed.
  - Existing `player_reference_lyrics_test.dart` and `project_player_live_sources_test.dart` cover the moved pane's existing behavior.
  - Local Flutter/Dart SDK is unavailable; validation used GitHub Actions.
- Notes: structural move only; PR #521 remains open for review.
- Commit: `Split player lyrics pane`

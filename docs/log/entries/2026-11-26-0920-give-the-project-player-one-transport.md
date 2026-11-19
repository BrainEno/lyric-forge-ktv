# [2026-11-26 09:20] Give the project player one transport

- Scope: UI/UX audit, player family ("同文件两套传输控制：`_TransportPane` 与 `_PlaybackControls` 并存，职责切分不清", P2). `player_screen.dart` built the transport in two private widgets (`_TransportPane` for the two-pane layout, `_CompactTransportHeader` with a regular and a short variant). Both took the same twelve parameters and repeated the progress, controls, source and mode rows, and a fourth wrapper (`_PlaybackControls`) existed only to feed `TransportBar`. The new `ProjectPlayerTransport` takes one immutable `ProjectPlayerTransportState`, one `ProjectPlayerTransportActions` and a `ProjectPlayerTransportLayout` (`sidePane`, `header`, `shortHeader`). The three arrangements share their parts: cover, identity, error banner, progress, `TransportBar`, source chips and mode chips. The previous button now uses `PlaybackSessionState.canSkipPrevious`, the same rule (a current item exists), instead of re-deriving it. `player_screen.dart` drops from 1404 to about 950 lines.
- Files:
  - `lib/features/player/presentation/widgets/project_player_transport.dart` (new).
  - `lib/features/player/presentation/screens/player_screen.dart` (`_PlayerWorkspace` builds the state and actions once; the private transport widgets, `_ProjectArtwork`, `_SongIdentity`, `_PlaybackControls`, `_AudioSourceSelector`, `_PlayerModeControls` and `_sourceLabel` moved out or were removed).
  - `test/features/player/presentation/widgets/project_player_transport_test.dart` (new, 15 tests: layout choice from the viewport; side pane identity and cover; header without album and with the unknown-artist fallback; short header row; skip buttons per layout and without a queue; source chips only with a choice; KTV needs lyrics; KTV and full screen with lyrics; error banner in every layout; busy play button).
- Validation:
  - Behaviour kept: the header still picks its short variant from the window height (`AppResponsive.of`), as before; the side pane is chosen by the player's own box.
  - `test/features/player/project_player_live_sources_test.dart` (source chips through the real screen) is unchanged.
  - No Dart/Flutter toolchain in the sandbox; `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate and a temporary probe workflow.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - Not checked in a running app.
- Commit: `Give the project player one transport`

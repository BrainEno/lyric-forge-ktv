# [2026-11-18 23:17] Add a shared empty-state widget

- Scope: UI/UX audit C-06 (roadmap phase 2). Seventeen private empty/error/loading widgets each chose their own icon size (34–64 px), spacing, title style and button layout. This adds the first shared component under `lib/core/widgets/`, `AppEmptyState`, with two densities: `page` (56 px icon, `titleMedium` w700 title, optional message, actions in a centered `Wrap`, 420 px readable width) and `panel` (36 px icon, muted `bodyMedium` title, for side panels and sheets). Four simple private empty states now delegate to it; their texts, icons and call sites are unchanged.
- Files:
  - New: `lib/core/widgets/app_empty_state.dart`, `test/core/widgets/app_empty_state_test.dart` (densities, empty slots omitted, action fires, long text stays within the readable width without overflow).
  - Migrated: `_NoResults` in `local_library_explorer_screen.dart`, `_EmptyNowPlaying` in `now_playing_screen.dart`, `_EmptyQueue` in `playback_queue_panel.dart` (panel density, visually unchanged), `_EmptyLyricsState` in `lyric_editor_content.dart`.
- Validation:
  - No Dart/Flutter toolchain in the sandbox, so `dart format`, `flutter analyze` and the widget tests run in the PR's Flutter Quality Gate. New and changed lines were measured so that lines the formatter would join or split are already written that way.
  - The architecture contracts allow presentation to import `lib/core`; the new widget imports only Flutter, `core/layout` and `core/theme` tokens (no colour literals).
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - Visible changes: the library "no results" text is now a title-style line instead of body text. The Now Playing empty button gets the layout's minimum interactive extent (48 dp on touch and narrow layouts). The empty-lyrics title uses `titleMedium` instead of `titleLarge`, and its "添加第一行" button is content-width instead of stretching to 420 px.
  - Not migrated yet: `_EmptyLibrary` and `_EmptyPlayer` (onboarding hero layouts with two or three actions), `_EmptyQueueState` (card style inside the transcription queue), `_EmptyCard`, `_Message`, and the error/loading classes. They need either a hero variant or a separate `AppErrorState`, which is a follow-up task.
- Commit: `Add a shared empty-state widget`

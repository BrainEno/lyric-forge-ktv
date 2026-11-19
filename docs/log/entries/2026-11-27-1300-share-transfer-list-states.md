# [2026-11-27 13:00] Share transfer list states

- Scope: Audit T-02 (transfer sub-domain), first slice. The phone's songs, artists/albums and download manager screens each drew their own red error line, bare `CircularProgressIndicator()` and grey "没有匹配…" sentence. New `transfer_list_states.dart` gives them one set built on the app's state widgets: `TransferErrorBanner` (tinted banner, `errorText`, live region, close button), `TransferListLoading` (`AppInlineLoading` that says what is loading) and `TransferEmptyResult` (`AppEmptyState` panel whose title depends on why the list is empty: a search that matched nothing quotes the query and offers "清除搜索", an active filter on the songs list says which filter and offers "显示全部", and a truly empty library or download list explains how to fill it). Sentences live in `TransferListText`.
- Files:
  - `lib/features/transfer/presentation/widgets/transfer_list_states.dart` (new).
  - `lib/features/transfer/presentation/screens/mobile_remote_music_library_screen.dart`, `mobile_remote_grouped_library_screen.dart`, `mobile_download_manager_screen.dart`.
  - `test/features/transfer/presentation/transfer_list_states_test.dart` (new: banner colours, dismiss and live region; loading text; empty reason precedence and titles; clear-search and show-all actions; source checks that the three screens use the shared states).
- Validation:
  - No Dart/Flutter toolchain in the sandbox; `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate and a temporary probe workflow.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - The desktop transfer hub and the v2 naming part of T-02 are untouched.
- Commit: `Share transfer list states`

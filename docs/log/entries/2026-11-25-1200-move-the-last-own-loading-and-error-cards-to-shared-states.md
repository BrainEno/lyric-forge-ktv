# [2026-11-25 12:00] Move the last own loading and error cards to shared states

- Scope: the loading and error state convergence that earlier rounds left with two holdouts. The ASR setup dialog's `_LoadingCard`, the storage preflight card and the span recognition dialog each drew a spinner beside one line of text by hand; the new `AppInlineLoading` (in `app_loading_state.dart`) is that row once, with an 18 px spinner labelled by its message, the text excluded from semantics so it is not read twice, a live region, and a `framed` variant with the elevated rounded card. The desktop transfer page's `_ErrorCard` showed a red message with no way out; it is now the shared `AppErrorState` (panel density, in a card) whose 重试 repeats exactly the step that failed: reading the library, refreshing, starting (which asks for sharing consent again) or stopping the service. Stopping now also clears an old failure, as the other steps already did.
- Files:
  - `lib/core/widgets/app_loading_state.dart` (`AppInlineLoading`).
  - `lib/features/transcription/presentation/widgets/asr_runtime_setup_dialog.dart` (`_LoadingCard` removed).
  - `lib/features/transcription/presentation/widgets/asr_storage_preflight_card.dart` (checking state).
  - `lib/features/lyrics/presentation/widgets/lyric_span_recognition_dialog.dart` (running state).
  - `lib/features/transfer/presentation/screens/desktop_media_transfer_hub_screen.dart` (`_failure` with its retry, `AppErrorState`, `_ErrorCard` removed).
  - `test/core/widgets/app_loading_state_test.dart` (spinner size, label and position; unframed hugs its content; framed fills the width in a decorated card; long text wraps; live region).
  - `test/features/transfer/presentation/desktop_media_transfer_hub_screen_test.dart` (new: a failed library read retries the read; a failed start retries the start and asks for consent again, and declining keeps the failure; no error state without a failure).
- Validation:
  - No Dart/Flutter toolchain in the sandbox; `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate and the temporary format probe.
  - The source contracts that read these files (`media_hub_security_consent_contract_test.dart`: `_prepare` still never starts the listener; `asr_storage_preflight_contract_test.dart`: the card's copy) are unchanged.
  - The format probe found older formatter debt in `asr_storage_preflight_card.dart` (old-style nested ternaries and `copyWith` indents); the follow-up commit `Apply the formatter to the storage preflight card` rewrites the file to the probe's exact output (blob `b324cd9`), since the quality gate formats every touched file.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - Button spinners (`AppButtonSpinner`) and the transfer page's own start button spinner are a different pattern and stay as they are.
- Commit: `Move the last own loading and error cards to shared states`

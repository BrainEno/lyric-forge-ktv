# [2026-10-25 00:55] Clarify failed ASR progress and copy diagnostics

- Scope: Fix confusing 100% progress after an ASR file-integrity error, make failed progress bars use the error color and say preparation remains incomplete, and provide one reusable selectable/copyable diagnostics card in setup and settings.
- Files: `lib/features/transcription/presentation/widgets/asr_install_progress_card.dart`, new `asr_install_error_card.dart`, `asr_runtime_setup_dialog.dart`, `ai_transcription_settings_section.dart`, install-experience tests, runtime-installation docs and work-log navigation.
- Validation: Add widget regressions for a failed event with progress=1.0 and for the copyable diagnostics card. GitHub Actions must run Flutter analysis, the full suite, ASR-specific contract checks and managed runtime builds.
- Notes: The percent shown after failure represents the last reported stage, not successful completion; it is capped below 100%. The underlying error details remain unchanged and are available to copy/select.
- Commit: `fix: clarify failed ASR progress and copy diagnostics`

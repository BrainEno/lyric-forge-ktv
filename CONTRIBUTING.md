# Contributing to LyricForge KTV

Thanks for helping improve LyricForge. The project is local-first music playback and KTV production software; playback should remain useful without requiring the transcription or production toolchain.

## Before opening an issue

Search existing issues and include the smallest reproducible description of the problem. For bugs, provide the operating system, Flutter version, device/runtime details, reproduction steps, expected behavior, and relevant sanitized logs. Do not attach copyrighted songs, private audio, authentication tokens, local secrets, or model weights.

## Development environment

- Use the Flutter version in `.fvmrc` (currently `3.47.7`) and the Dart SDK bundled with that Flutter installation.
- Install the platform toolchain needed for the target you are building. Run `flutter doctor -v` and `flutter devices` if Flutter cannot find a target.
- Run `flutter pub get` after dependency changes. Commit the resulting `pubspec.lock`; do not silently upgrade dependencies in unrelated fixes.

## Common validation

```bash
flutter analyze --no-pub --no-fatal-infos lib test
flutter test
dart tool/work_log.dart check
```

Run the tests for the area you changed as well as the broader quality gate when practical. For native audio, Media Hub, microphone, ASR runtime, or platform-build changes, state which platform/device paths were actually tested and which remain unverified.

## Code and architecture

- Follow `AGENTS.md` for the full product scope, layering rules, responsive layout standard, and validation expectations.
- Put feature code under `lib/features/<feature>/` with presentation, domain, and data responsibilities separated. Keep platform APIs, persistence, file I/O, and subprocesses out of widgets and domain contracts.
- Keep normal playback independent from desktop-only ASR/separation tools. Treat automatic transcripts and alignment proposals as editable drafts.
- Preserve Unicode filenames and lyric text; do not silently overwrite manual edits or delete user data.
- Prefer focused, independently testable PRs. Avoid adding a dependency unless the use case cannot be covered by existing libraries.

## Work log

Every implementation task must add an immutable entry under `docs/log/entries/` with scope, changed files, validation, residual notes, and the commit subject. Use the repository work-log tool to generate a scaffold and maintain the summary:

```bash
dart tool/work_log.dart new --timestamp "YYYY-MM-DD HH:mm" --slug <ascii-slug> --title "Short title"
dart tool/work_log.dart write
dart tool/work_log.dart check
```

Replace all scaffold placeholders before committing. Keep `docs/handoff.md` current for interrupted multi-step work, and do not create a competing root-level work log.

## Pull requests

Keep one primary concern per PR and link the relevant issue. Describe user-visible behavior, compatibility impact, and data/security risks. Include test commands and their outcomes. If a check cannot run, state that explicitly rather than marking it passed.


# Project Mission

This project builds a local-first KTV production tool: desktop-first,
mobile-consumption-second.

The product goal is to let users:

1. import local audio,
2. preprocess and normalize it,
3. separate vocal / instrumental on desktop,
4. run local ASR on the vocal track,
5. merge segmented transcription into editable lyrics,
6. export a playable local KTV project,
7. open and use that project on desktop and mobile.

This is not a generic music player. It is a local KTV creation tool with strong
emphasis on privacy, offline workflows, editable lyrics, and playback polish.

---

# Product Scope

## Desktop-first MVP

Desktop is the primary production environment.

Desktop MVP must support:

- import mp3 / flac / wav / m4a
- create and reopen local project folders
- preprocess audio with visible progress
- vocal / instrumental separation
- local lyric transcription
- editable lyric timeline
- accompaniment playback with synced lyrics
- export LRC and project manifest

## Mobile-second MVP

Mobile is the playback and light-edit environment.

Mobile MVP should support:

- opening exported projects
- accompaniment playback
- synced lyric display
- global lyric offset adjustment
- minor lyric correction
- saving revised project metadata

## Explicit non-goals for MVP

Do not promise:

- perfect fully automatic lyrics
- mobile-side full local source separation
- cloud-only architecture
- online song library integration
- exact cloning of any third-party branded product

---

# Architecture Rules

## Flutter feature organization

- Organize code by business feature under `lib/features/<feature>/`.
- Inside each feature, keep clear layers: `presentation/`, `domain/`, `data/`.
- Domain layer must not import Flutter UI, Drift, Hive, or platform APIs.
- Presentation layer must not access DAOs, database classes, or shell processes
  directly.
- Repository contracts live in `domain/`; implementations live in `data/`.
- Cross-feature calls should go through use cases, services, or repository
  abstractions, not widget-to-widget shortcuts.

## Processing responsibility split

Flutter owns:

- app shell
- navigation
- state presentation
- user interaction
- playback UI
- lyric editing UI
- task progress display
- error and retry presentation

Processing services / adapters own:

- heavy local processing
- long-running task orchestration
- audio pipeline coordination
- file IO and project artifacts
- deterministic error surfaces
- cache and manifest integrity

## Required runtime direction

- Flutter for UI and app orchestration
- local processing behind service abstractions
- whisper.cpp (or equivalent local ASR backend) for local transcription
- FFmpeg for preprocessing
- desktop-only separation backend in MVP
- local project files as the system of record

## Forbidden architecture drift

- Do not introduce Python into runtime architecture.
- Keep mobile build path free of desktop-only assumptions.
- Do not make UI call CLI tools directly.
- Do not couple presentation code to low-level file paths.
- Do not bypass the project manifest / project model.
- Do not hardcode desktop-only workflows into shared mobile flows.

---

# UI / UX Direction

## Primary design direction

The UI should comprehensively reference the Spotify player design language while
remaining original and implementation-safe.

### Spotify-inspired qualities to preserve

- dark-first visual system
- media-centric layout
- immersive player feel
- layered surfaces instead of heavy borders
- strong hierarchy between artwork, track info, and secondary metadata
- rounded cards and modern control surfaces
- dense but clean playback controls
- smooth, restrained transitions
- obvious active-state emphasis
- elegant desktop sidebar / navigation rhythm

### Implementation constraint

Use Spotify only as a style reference. Do not copy Spotify logos, branding
assets, proprietary illustrations, exact iconography, or product copy.

### UX quality bar

Every new UI change should be evaluated against:

- visual hierarchy
- spacing consistency
- typography rhythm
- dark-theme polish
- playback-centric usability
- desktop and mobile coherence
- perceived smoothness
- readability of lyrics while playing

### Default UI preferences

- Prefer dark theme as default.
- Avoid generic admin-dashboard aesthetics.
- Avoid cluttered forms.
- Prioritize media immersion over tool-panel feeling.
- Ensure lyrics editor and player feel like parts of one coherent product.

---

# Coding Rules

- Prefer additive changes over large rewrites.
- Keep file names and module names stable unless required.
- Prefer explicit code over clever code.
- Keep widgets thin; put business rules in use cases/services.
- Use Chinese-facing labels/text only in UI-facing files.
- Add comments only where intent is non-obvious.
- Prefer resumable pipelines over one-shot black boxes.
- Treat automatically generated lyrics as editable draft output, not guaranteed
  truth.
- Surface low-confidence or suspicious lyric segments instead of hiding them.

---

# Validation

Before finishing, run or explain the intended validation:

## Common validation

- `dart format .`
- `flutter analyze`
- targeted `flutter test` for changed modules

## UI behavior validation

If UI behavior changed, include a short manual verification checklist.

## If validation cannot run

Explicitly state:

- what was not run,
- why it was not run,
- what remains risky.

---

# Delivery Contract

For each task:

1. State plan
2. List files to change
3. Implement
4. Run verification commands
5. Report residual risks

---

# Verification

- `flutter analyze`
- `flutter test`
- any new command must be documented

---

# Forbidden

- Do not delete project-wide configs.
- Do not touch secrets.
- Do not change CI unless the task explicitly asks.
- Do not overwrite user-edited lyrics silently.
- Do not claim full lyric accuracy without user review.
- Do not hide long-running failures behind generic error messages.

---

# Working Rules

## Completion and logging rule

After finishing any task that is:

- implemented,
- passes the relevant checks/tests for that task,
- and is in a committable state,

you must append a new entry to `docs/work_log.md`.

Do this every time such a task is completed unless the user explicitly tells you
not to.

## Required checks before logging

Before writing the log entry, you must:

1. run the relevant validation commands for the task,
2. confirm there are no new errors blocking commit,
3. ensure the changed files are in a reviewable, committable state.

Typical validation commands:

- `flutter analyze`
- `flutter test`
- any task-specific targeted test command if full test is unnecessary

## Log format

Each appended entry in `docs/work_log.md` must follow this format exactly:

### [YYYY-MM-DD HH:MM] Task Title

- Scope: <one short paragraph describing what was completed>
- Files: `<file1>`, `<file2>`, `<file3>`
- Validation:
  - `<command 1>` => `<result>`
  - `<command 2>` => `<result>`
- Notes: <important implementation notes, tradeoffs, or follow-up risks>
- Commit: `<one short English Git commit message>`

## Commit message rule

For every completed task, you must propose exactly one short English commit
message.

The commit message must:

- be concise,
- be specific,
- use imperative mood,
- describe the main completed change,
- fit naturally as a Git commit subject line.

Avoid:

- vague messages like `update code`
- overly long summaries
- multiple unrelated changes in one message

## When NOT to log

Do not append a log entry if:

- the task is incomplete,
- tests/checks have not been run when required,
- the result is exploratory only,
- the code is not yet in a committable state

## If the log file does not exist

If `docs/work_log.md` does not exist, create it with the title:

# Work Log

Then append the first entry using the required format.

## Project-specific completion standard

A task is considered committable only when:

- the requested scope is implemented,
- no unrelated files are modified without reason,
- `flutter analyze` has no new errors caused by the task,
- relevant tests pass when business logic or data flow changed,
- the final log entry is appended to `docs/work_log.md`,
- and a short English commit message is proposed.

## Preferred logging style for this repository

When describing completed work:

- write with Chinese
- mention the user-visible business purpose, not just code mechanics
- mention audio / lyrics / playback / desktop-mobile impact if relevant
- note any manifest / cache / pipeline impact explicitly
- note any deferred work explicitly

---

# Task Sizing Rule

Before starting implementation, estimate whether the task is too large for a
single thread.

Treat a task as too large if any of the following is true:

- expected net code change is likely above ~300 lines
- more than 8 files are likely to be modified
- the task spans data model + pipeline + UI in one go
- the task mixes import, transcription, playback, export, or mobile parity in
  one batch
- the task contains more than one independently testable business goal

If the task is too large:

1. first output a short phased plan,
2. split it into smaller committable sub-tasks,
3. execute only the first sub-task unless explicitly asked to continue.

A single Codex / OpenCode thread should usually target one committable sub-task
only.

---

# Reasoning Effort Rule

Prefer the lowest reasoning effort that can reliably complete the task.

- low: small UI fixes, parameter fixes, localized refactors
- medium: standard multi-file implementation work
- high: difficult debugging, cross-layer pipeline logic, playback-sync issues
- avoid xhigh unless the task is genuinely hard and tightly scoped

# Project Mission

This project builds a **local-first music player with integrated lyric and KTV
production capabilities**.

The local music player is a primary product surface on both desktop and mobile.
Lyrics, local ASR, lyric editing, vocal/instrumental processing, and KTV playback
are capabilities attached to local songs; they are not prerequisites for using
the app as a normal local player.

The product goal is to let users:

1. build and browse a persistent local music library,
2. play local music with queues, playlists, favorites, artwork, and metadata,
3. attach/import common lyric files or create lyrics with local ASR,
4. edit and synchronize lyrics,
5. optionally preprocess and separate vocal / instrumental audio on desktop,
6. export and reopen playable local KTV projects,
7. use the same library/playback model coherently across desktop and mobile.

Privacy, offline workflows, Unicode-safe local media handling, editable lyrics,
and playback polish are core requirements.

---

# Product Scope

## Core local-player experience — desktop and mobile

The app must remain useful before the user ever starts transcription.

Core playback/library scope includes:

- persistent local music Library
- local file/folder import
- title / artist / album / artwork presentation
- non-destructive user metadata overrides
- Unicode-safe Chinese / Japanese / emoji text handling
- queue management
- previous / play-pause / next
- seek and volume
- shuffle / repeat modes
- favorites and local playlists
- recent listening and resume position
- lyric file import and lyric display when available
- responsive Now Playing / Library surfaces

## Desktop production capabilities

Desktop remains the primary lyric-production environment.

Desktop production should support:

- create and reopen local project folders
- preprocess audio with visible progress
- vocal / instrumental separation
- local lyric transcription
- editable lyric timeline
- low-confidence / disagreement review
- accompaniment playback with synced lyrics
- export LRC and project manifest

## Mobile playback and light editing

Mobile should support the same local-player information architecture at a
mobile-appropriate density, plus:

- local library browsing
- normal local playback
- queue / favorites / playlists
- synced lyric display
- global lyric offset adjustment
- minor lyric correction
- opening exported lyric/KTV projects
- saving revised project metadata where supported

Do not make mobile playback depend on desktop-only processing tools.

## Explicit non-goals for MVP

Do not promise:

- perfect fully automatic lyrics
- mobile-side full local source separation
- cloud-only architecture
- online commercial song-library integration
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
- local-library presentation
- playback state presentation
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
- one shared app-scoped playback/session model across responsive surfaces
- local processing behind service abstractions
- whisper.cpp / Qwen or equivalent local ASR backend for local transcription
- FFmpeg for preprocessing
- desktop-only separation backend where required
- local files / manifests as the system of record

## Forbidden architecture drift

- Do not introduce Python into runtime architecture.
- Keep mobile build path free of desktop-only assumptions.
- Do not make UI call CLI tools directly.
- Do not couple presentation code to low-level processing implementations.
- Do not bypass the project manifest / project model for KTV project state.
- Do not hardcode desktop-only workflows into shared mobile playback flows.
- Do not create separate desktop/mobile playback queues or duplicated player
  state solely for layout reasons.

---

# UI / UX Direction

## Primary design direction

The UI should reference the media-centric strengths of Spotify while remaining
original and implementation-safe.

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
- window-resize behavior
- touch-target quality
- perceived smoothness
- readability of lyrics while playing

### Default UI preferences

- Prefer dark theme as default.
- Avoid generic admin-dashboard aesthetics.
- Avoid cluttered forms.
- Prioritize media immersion over tool-panel feeling.
- Ensure Library, player, lyrics editor, and KTV feel like one coherent product.
- Keep AI/transcription actions secondary until the user explicitly needs them.

## Responsive layout standard — required

`docs/responsive-layout.md` and `lib/core/layout/app_responsive.dart` are the
responsive source of truth.

Width classes:

- Compact: `<600`
- Medium: `600–839`
- Expanded: `840–1199`
- Large: `1200–1599`
- Extra Large: `>=1600`

Height classes:

- Short: `<600`
- Regular: `600–899`
- Tall: `>=900`

Rules:

- Do not invent page-local breakpoint constants when `AppLayoutSpec` can express
  the layout decision.
- Responsive behavior is based on available viewport, not device name alone.
- Consider width and height independently; phone landscape and short desktop
  windows must not inherit tall desktop compositions.
- Touch platforms keep at least 48dp interactive targets.
- Collapse secondary actions before shrinking primary playback controls.
- Large displays gain whitespace / bounded content width rather than endlessly
  stretched cards and text.
- Avoid `Expanded` / `Spacer` inside unbounded scroll axes.
- Resizing must never recreate or reset playback queue, metadata, lyrics,
  project, or transcription business state.
- A desktop window dragged through 600 / 840 / 1080 / 1200 / 1600 must adapt
  without requiring restart.

Required responsive manual matrix when a Flutter runtime is available:

- 390×844
- 844×390
- 768×1024
- 1024×768
- 1366×768
- 1600×900
- 1920×1080
- 2560×1440

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
- Do not truncate Unicode user text by code-unit count; use layout overflow and
  `maxLines`/ellipsis instead.

---

# Validation

Before finishing, run or explain the intended validation.

## Common validation

- `dart format .`
- `flutter analyze`
- targeted `flutter test` for changed modules

## UI behavior validation

If UI behavior changed, include a short manual verification checklist.

For responsive changes, validate the viewport matrix defined above and perform
continuous desktop drag-resizing through the shared breakpoints.

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
- Do not make responsive layout by maintaining separate desktop/mobile business
  state.

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

When you need to search framework or library docs, use `context7`.

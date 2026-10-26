# Project Mission

Build a local-first music player with lyric editing, local ASR, vocal/instrumental processing, and KTV production. Normal local playback must remain useful without transcription or other production tools. Privacy, offline workflows, Unicode-safe media handling, editable lyrics, and consistent desktop/mobile playback are core requirements.

## Product scope

- Core desktop/mobile: persistent local library, file/folder import, metadata/artwork, non-destructive metadata overrides, Unicode-safe text, queue, transport controls, seek/volume, shuffle/repeat, favorites/playlists, recent listening/resume, lyric import/display, responsive Library/Now Playing.
- Desktop production: local projects, visible preprocessing progress, vocal/instrumental separation, local transcription, editable timeline, low-confidence review, synced accompaniment playback, LRC/project-manifest export.
- Mobile: library/playback/queue/favorites/playlists, synced lyrics, global offset and minor corrections, opening exported lyric/KTV projects, and metadata edits where supported. Do not make mobile playback depend on desktop-only processing.
- MVP non-goals: perfect automatic lyrics, mobile full source separation, cloud-only architecture, online commercial song-library integration, or exact cloning of another branded product.

## Architecture rules

- Organize features under `lib/features/<feature>/` with `presentation/`, `domain/`, and `data/`.
- Domain must not import Flutter UI, Drift, Hive, or platform APIs.
- Presentation must not access DAOs/database classes or shell processes directly.
- Repository contracts belong in `domain/`; implementations belong in `data/`.
- Cross-feature calls use use cases, services, or repository abstractions, not widget-to-widget shortcuts.
- Flutter owns app shell, navigation, presentation, interaction, playback/lyric UI, progress, and retry/error presentation.
- Processing services/adapters own heavy local processing, long-running orchestration, audio pipelines, file IO/project artifacts, deterministic errors, caches, and manifest integrity.
- Required direction: Flutter UI/orchestration; one app-scoped playback/session model; local processing behind abstractions; local ASR backend (whisper.cpp/Qwen/equivalent); FFmpeg preprocessing; desktop-only separation where required; local files/manifests as system of record.
- Do not add Python to runtime architecture; keep mobile free of desktop-only assumptions; do not call CLI tools from UI; do not bypass the project manifest/model for KTV state; do not duplicate playback queues/state for layout alone.

## UI and responsive behavior

- Follow `docs/responsive-layout.md` and `lib/core/layout/app_responsive.dart` as the responsive source of truth.
- Width classes: Compact `<600`, Medium `600–839`, Expanded `840–1199`, Large `1200–1599`, Extra Large `>=1600`.
- Height classes: Short `<600`, Regular `600–899`, Tall `>=900`.
- Use available viewport, not device name; consider width and height independently; do not invent local breakpoints when `AppLayoutSpec` covers the decision.
- Touch targets must be at least 48dp. Collapse secondary actions before shrinking primary playback controls. Large screens should gain whitespace/bounded content width, not stretched cards.
- Avoid `Expanded`/`Spacer` in unbounded scroll axes. Resizing must not recreate/reset playback queue, metadata, lyrics, project, or transcription state.
- Preserve the dark-first, media-centric, polished player aesthetic. Spotify is a reference only: do not copy logos, proprietary illustrations, exact iconography, or product copy.
- When Flutter runtime is available, manually check 390×844, 844×390, 768×1024, 1024×768, 1366×768, 1600×900, 1920×1080, and 2560×1440, including continuous resizing across breakpoints.

## Coding rules

- Prefer additive changes, stable names, explicit code, thin widgets, and business rules in use cases/services.
- Use Chinese-facing labels only in UI-facing files.
- Add comments only for non-obvious intent.
- Prefer resumable pipelines over one-shot black boxes.
- Treat automatic lyrics as editable drafts, not guaranteed truth; surface low-confidence/suspicious segments.
- Never truncate Unicode user text by code-unit count; use layout overflow and `maxLines`/ellipsis.
- Do not silently overwrite user-edited lyrics or touch secrets. Do not delete project-wide configs or change CI unless explicitly requested. Do not hide long-running failures behind generic errors.

## Validation and delivery

Before finishing, state the plan and intended files; implement; run validation; report results and residual risks.
- Common checks: `dart format` for changed Dart files, `flutter analyze` (or scoped analyzer if the full project has a known blocker), and targeted `flutter test`.
- If UI behavior changes, include a manual verification checklist. For responsive changes, use the viewport matrix above.
- If checks cannot run, state exactly what was not run, why, and remaining risks.
- A task is committable only when scope is implemented, unrelated files are untouched without reason, no new analyzer errors are introduced, relevant tests pass, and the log entry is written.
- Estimate task size first. Split if expected changes exceed ~300 lines, more than 8 files, multiple independent goals, or a cross-layer pipeline/UI/data change. A single thread should usually complete one committable sub-task; execute only phase 1 unless asked to continue.
- Use the lowest reasoning effort that can reliably complete the task: low for small local fixes, medium for ordinary multi-file work, high for difficult cross-layer/debugging, and avoid xhigh unless genuinely needed.
- Use `context7` when framework/library documentation search is needed.

## Work-log and context-efficient harness (required)

### Canonical files

- `docs/work_log_index.md`: compact navigation, recent focus, important follow-up leads, and pointers.
- `docs/log/entries/<yyyy-mm-dd-hhmm>-<slug>.md`: one immutable file per completed task. Full text of the entry lives here. Never moved, never deleted, never rewritten.
- `docs/work_log.md`: **generated** active summary (newest 8 entries, one line each). Do not edit by hand; regenerate with `dart tool/work_log.dart write`.
- Use `dart tool/work_log.dart new --timestamp "YYYY-MM-DD HH:mm" --slug <ascii-slug> --title <title>` to create new entry files. This template guarantees the required `Scope`, `Files`, `Validation`, `Notes`, and `Commit` fields; replace every TODO and never substitute a differently named field.
- `docs/work_log_archive.md`: navigation for older entries, grouped by stage. Bodies stay in `docs/log/entries/`. The writer adds missing links to an auto-generated archive section so entries never become orphaned when they leave the active window.
- `docs/decisions.md`: durable decisions that still bind future work.
- `docs/handoff.md`: single-slot interruption handoff; overwrite it before ending a session.
- The repository's canonical log root is `docs/`. Do not create a competing root-level `work_log.md`.

### At task start

1. Read this `AGENTS.md` and `docs/work_log_index.md`.
2. Read only the 1–3 entry files relevant to the task (`docs/log/entries/`), not the whole directory.
3. Search `docs/log/entries/` or `docs/work_log_archive.md` by exact topic/date only if older history is relevant.
4. Check `git status --short`, `git diff --stat`, and recent commits before modifying files. Preserve existing user changes.
5. Inspect only relevant source, tests, and docs. Prefer narrow `rg`/`Select-String` output over full-file dumps.

### During work

- Keep the task to one independently testable goal. Use a short phased plan for larger work.
- Avoid unnecessary context growth: do not paste full logs, giant diffs, generated files, or unrelated source into the conversation.
- Make changes in small, reviewable stages. After each logical stage, record a concise checkpoint: changed files, checks run, result, and next step.
- If a tool output is huge, filter it before returning it to the model.
- Do not repeatedly retry a failing command without changing the hypothesis or collecting new evidence.

### Local-model / interrupted-session recovery

- A long log can contribute to context pressure, but it is not by itself proof of context overflow.
- If OpenCode reports a Jinja/chat-template role-alternation error during compaction, treat it first as provider/template compatibility—not as a code error or a GPU-utilization problem. Do not enter an endless retry loop.
- On interruption: stop edits, inspect `git status --short`, `git diff --stat`, `git diff --cached --stat`, recent commits, and the latest entry files. Do not run destructive reset/clean commands.
- Write the handoff into `docs/handoff.md` (overwrite, single slot) using its fixed sections: goal, Git snapshot (`git status --short`, `git diff --stat`, `git log --oneline -5` output), changed files, check results, the single next step, known risks.
- Start a fresh session by reading `docs/handoff.md`, then `AGENTS.md` and `docs/work_log_index.md`; do not reload the full archive.
- Test local provider/tool-call and compaction behavior on a small task before trusting a long autonomous run.

### When a task is complete

1. Run relevant checks and confirm no new blocking errors.
2. Only after implementation and validation are complete and committable, create one entry with `dart tool/work_log.dart new --timestamp "YYYY-MM-DD HH:mm" --slug <ascii-slug> --title <title>` (use Asia/Taipei time and a unique timestamp), then replace every TODO. Do not hand-author the required-field skeleton. The output file `docs/log/entries/<yyyy-mm-dd-hhmm>-<slug>.md` must follow this exact structure:

   `# [YYYY-MM-DD HH:MM] Task Title`

   - `Scope`: one short paragraph describing the user-visible purpose.
   - `Files`: changed files, including the log/index if modified.
   - `Validation`: each command and result.
   - `Notes`: trade-offs, unverified behavior, and deferred work.
   - `Commit`: exactly one concise English imperative commit subject.

3. Run `dart tool/work_log.dart write` to regenerate `docs/work_log.md`, sync the index snapshot date, and add archive links for aged-out entries; never hand-edit the generated summary.
4. Optionally move auto-generated archive links into an existing stage section when that improves navigation. Do not delete entry files.
5. Update the curated body of `docs/work_log_index.md` only if the stable current focus, a key decision, an important deferred risk, or navigation pointers materially change. The writer updates its snapshot date automatically. Keep it under ~80 lines; do not mirror every task.
6. Record durable, still-binding decisions in `docs/decisions.md`; superseded ones are marked `已取代` instead of being deleted.
7. Run `dart tool/work_log.dart write`, then `dart tool/work_log.dart check` and review `git diff -- docs/work_log.md docs/work_log_index.md docs/work_log_archive.md`. The quality gate runs this check before analysis/tests so documentation errors fail fast; a green gate still requires generated files to be committed and the check to pass.
8. Do not log exploratory/incomplete work or claim tests passed when they were not run.

## Required commit-message style

Propose exactly one short English commit message per completed task. Use imperative mood, describe the main change, and avoid vague or unrelated subjects.

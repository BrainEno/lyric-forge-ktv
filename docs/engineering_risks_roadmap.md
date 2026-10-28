# Engineering Review Findings and Product-Quality Roadmap

> Review date: 2026-10-28. Scope: verify findings against a fixed source snapshot rather than accepting model-generated review summaries at face value.
>
> Product direction: this is open-source, local-first KTV software. “Commercial-grade” means dependable core workflows, audio quality, recovery, security, installation and maintainability; it does **not** imply a monetization plan or a commercial-release deadline. Prioritize product correctness and user value. Keep third-party provenance and required notices scoped to artifacts that are actually redistributed; do not turn hypothetical legal review or commercial-use approval into a blocker for local experiments or unrelated engineering work.
>
> This document records evidence-backed risks and follow-up acceptance criteria. “Confirmed gap” means the source configuration is demonstrably incomplete; “conditional risk” means the design has a real limit whose user impact still needs measurement. It does not assert unmeasured performance or audio-quality failures.

## Priority 1 — Fix before a macOS Release that advertises Media Hub sharing

### Confirmed gap: the Release app lacks the incoming-network entitlement

Evidence reviewed:

- `macos/Runner/DebugProfile.entitlements` sets `com.apple.security.network.server` to `true`.
- `macos/Runner/Release.entitlements` does not declare `com.apple.security.network.server`.
- `lib/features/transfer/data/services/http_media_hub_service.dart` starts an `HttpServer` listener for the Media Hub.
- `.github/workflows/macos-network-entitlements-validation.yml` checks `com.apple.security.network.client` in both source plists and built Debug/Release apps, but does not assert the server entitlement.

Apple defines `com.apple.security.network.server` as the entitlement that allows a sandboxed app to listen for incoming network connections. Flutter's macOS build guidance also warns that the server entitlement is enabled by default for Debug/Profile and must be present in Release when the app accepts incoming connections.

**Required follow-up**

1. Add the server entitlement to the Release configuration if Media Hub sharing remains a supported Release feature.
2. Extend CI to validate the source Release plist and the built/signed Release app for both the client and server entitlements. Keep Debug/Profile checks explicit as well.
3. Smoke-test the packaged Release app: start sharing, connect from a second device over LAN and the supported Tailscale path, verify health/list/Range streaming, then stop sharing and confirm the listener is closed.

**Acceptance:** CI fails if the built Release artifact is missing the server entitlement, and the packaged Release app can accept an authorized inbound Media Hub connection. A passing Debug run alone is not sufficient.

Reference: [Apple — `com.apple.security.network.server`](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.server) · [Flutter — Building macOS apps](https://docs.flutter.dev/platform-integration/macos/building).

## Priority 2 — Harden ASR process lifecycle before treating long jobs as unattended

### Conditional risk: a live but stuck CLI process can wait indefinitely

The review claim that the application has *no* process management or health checks is inaccurate:

- `WhisperCppTranscriptionService` centralizes `Process.start`, drains stdout, retains a bounded stderr tail, supports cancellation via `Process.kill()`, and clears its active-process reference.
- The repository already has managed-runtime readiness/health code, including `local_asr_runtime_health_checker.dart` and runtime-manager abstractions.
- Highest-quality transcription already coordinates the selected engine order, second-opinion results, conservative fusion/review candidates, and shared normalized audio in its applicable path.

The real gap found in the inspected CLI adapter is narrower: `_runProcess` awaits `process.exitCode` without an operation timeout. A child process that remains alive but stops making progress can therefore hold the job open. The current architecture launches CLI processes rather than keeping a persistent ASR daemon; that is not inherently a defect, and a heartbeat is not meaningful for a short-lived CLI unless a supervised long-running worker is introduced.

**Required follow-up**

1. Define timeout budgets per operation (environment probe, FFmpeg preprocessing, and ASR inference); avoid one arbitrary timeout for all song lengths.
2. On timeout/cancel, stop waiting, terminate the process, use a platform-appropriate escalation where available, drain/close streams, clear lifecycle state, and preserve completed resumable checkpoints.
3. Make the timeout distinguishable from ordinary recognition failure in diagnostics and queue recovery.
4. Add regression coverage for a hung process, cancellation during startup/run, stderr flooding, non-zero exit, and cleanup of partial outputs.

**Acceptance:** a deliberately stalled child cannot leave the queue busy forever; the UI/queue receives a deterministic timeout or cancellation state; subsequent jobs can run; already completed checkpoints are retained. Evaluate a persistent worker/IPC design only if measurements show process startup or repeated initialization is a material cost.

## Priority 2 — Measure JSON-store scaling before migrating storage engines

### Confirmed design trade-off; current performance impact is unmeasured

The local library, collection, and project repositories persist whole JSON documents. For example, `file_local_media_library_repository.dart` loads JSON entries into in-memory collections and serializes the collection on writes; the collection and project repositories use similar whole-document patterns. Temporary-file replacement and serialized writes are valuable corruption/concurrent-write safeguards and should not be discarded.

The statement that “tens of thousands of songs will cause a severe memory bottleneck” is not yet supported by a benchmark. The risk is that cold-load memory, linear lookups, and full-file writes grow with the number of records.

**Required follow-up**

1. Add a repeatable synthetic benchmark at 1k, 10k, and 50k media entries, measuring cold load, exact-path lookup, search/filter latency, one-record mutation/write latency, and peak memory.
2. Record results on a documented reference machine and identify acceptable budgets before choosing a migration trigger.
3. If measurements exceed those budgets, preserve the existing domain repository contracts and evaluate a local SQLite-backed adapter, indexes, and paged/filtered queries. Plan schema migration and recovery tests; do not make an unconditional database migration solely from this review.

**Acceptance:** a benchmark report establishes a baseline and a quantitative migration decision. Atomic replacement, serialized mutation, and recovery from corrupt/partial data remain covered regardless of storage backend.

## Priority 2 — Verify audio-clock and monitoring alignment empirically

### Known architecture limitation, not a demonstrated timing defect

Normal playback uses `just_audio`; microphone capture uses `record`; low-latency monitoring uses `flutter_soloud`. These separate plugin/native pipelines do not establish a shared hardware sample clock or guarantee professional/ASIO-class zero-latency monitoring. The existing decision in `docs/decisions.md` (D-002) already treats monitoring delay as something to compensate and report honestly.

**Required follow-up**

1. Measure end-to-end monitor latency and recorded-take alignment on supported Windows/macOS devices, including device changes, sample-rate conversion, and long takes where clock drift can appear.
2. Record actual input/output latency values and distinguish measured values from estimates; test repeated runs to capture variance.
3. Set an explicit product acceptance budget for ordinary KTV monitoring and take alignment. Only consider a unified native audio backend or clock strategy if reproducible measurements fail that budget.

**Acceptance:** a documented hardware test matrix reports latency, alignment error, drift over time, and device-change behavior. Do not promise zero latency or frame-accurate sync without measured evidence.

## Priority 2 — Keep Media Hub HTTP and token guarantees testable

### Core functionality exists; extend boundary/security validation rather than rewriting it

The current service implements authorized requests, session-scoped tokens, full responses (200), single-byte-range partial responses (206), invalid-range responses (416), suffix/open-ended ranges, and HEAD handling. The current parser rejects multi-range requests rather than implementing multipart ranges; the protocol should continue to document that boundary. The service accepts a bearer token and also recognizes a token in the query string, so query-token handling deserves explicit security review because URLs can be copied or captured by logs.

**Required follow-up**

1. Keep bearer Authorization as the normal media-request mechanism. Review whether query-token authentication can be restricted to a compatibility/pairing boundary; never log session tokens.
2. Test missing/wrong tokens, stop-session invalidation, expired/stale pairing data, empty files, malformed and out-of-bounds ranges, suffix and open-ended ranges, HEAD headers, multi-range rejection, and missing source files.
3. Verify the packaged app binds only as intended, reports reachable LAN/Tailscale endpoints accurately, explains local firewall restrictions, and shuts the listener down on stop/dispose.
4. Preserve the current Range implementation unless tests demonstrate a protocol defect.

**Acceptance:** contract tests cover the above cases and confirm that unauthorized requests cannot enumerate tracks, stream audio, or upload files.

## Findings explicitly not promoted to defects

- **Dual-engine ASR:** the high-quality route already performs engine coordination/fusion and records disputed candidates for human review. Do not replace that accurate description with a simplified “run fallback only under a low average confidence threshold” explanation. Recognition-quality claims still require the project's manually reviewed, provenance-matched real-song corpus.
- **File replacement semantics:** temp-file writes and serialized mutations are useful safeguards, but at the reviewed fixed commit multiple stores explicitly delete the canonical file before renaming the temporary file. That creates a data-loss window; this is now recorded as a P0 follow-up below.
- **Two audio engines, JSON storage, or CLI processes by themselves:** these are not sufficient reasons for a broad rewrite. Prioritize reproducible failure modes and measured performance/quality before choosing a new architecture.

## Suggested order

1. Fix and CI-gate the Release network-server entitlement before a macOS Media Hub release.
2. Add process timeout/cancellation lifecycle tests for the ASR CLI adapter.
3. Establish JSON repository scale benchmarks; decide on SQLite/indexing only from measured results.
4. Run audio latency/alignment/drift measurements on representative hardware.
5. Expand Media Hub token and Range boundary tests, including Release packaging and listener shutdown.


## Supplementary findings from the second review

> Source baseline for implementation claims: [e8ea44ee4baa3da1709c9f5a665d0c01926e9e99](https://github.com/BrainEno/lyric-forge-ktv/tree/e8ea44ee4baa3da1709c9f5a665d0c01926e9e99). The prior roadmap commit changes documentation only; the source findings below refer to that fixed code snapshot. Static findings are not claims of device reproduction.

### P2 — Keep bundled-runtime provenance and notices lightweight and scoped

**Status: confirmed provenance gap for one pinned source; this is a packaging-scope task, not a product-development blocker.**

The pinned `lumosimmo/qwen3-asr-rs` source at commit `7984967e8701cc90bb17d06453901036e36ca578` contains no LICENSE, COPYING, or NOTICE path. The managed-runtime workflow builds a patched executable and attempts to copy licence files while suppressing copy failure. This deserves a bounded check before publishing that particular runtime as a downloadable, bundled artifact, regardless of whether the app earns money. It does not justify stopping local evaluation, ASR feature development, or unrelated product-quality work.

**Practical follow-up**

1. Keep the exact source revision, patches, model/runtime revisions and binary hashes recorded so the bundle is reproducible.
2. When deciding to redistribute this specific runtime, identify the applicable upstream terms and include notices/attribution that those terms require. If the terms cannot be established, use a runtime with clear redistribution terms or keep this bundle out of that particular packaged release; continue development and local testing in parallel.
3. Remove the workflow's silent assumption that a missing notice file is equivalent to a verified notice. Make the build output clearly report whether the expected provenance/notice files were found.
4. Do not require a generic legal consultation or separate “commercial-use” approval merely because the target is commercial-grade software. Revisit this item when the runtime is actually selected for redistribution, not as a gate for unrelated milestones.

**Acceptance:** anyone building or distributing a runtime bundle can identify its source revision and required notices; missing provenance is visible instead of silently ignored. This item is deliberately scoped to the affected bundled artifact and does not block the rest of the roadmap.

Evidence: [runtime build workflow at the fixed commit](https://github.com/BrainEno/lyric-forge-ktv/blob/e8ea44ee4baa3da1709c9f5a665d0c01926e9e99/.github/workflows/build-asr-runtime.yml) · [pinned upstream source tree](https://github.com/lumosimmo/qwen3-asr-rs/tree/7984967e8701cc90bb17d06453901036e36ca578).

### P0 — Close the delete-before-rename window in JSON persistence

**Status: confirmed code pattern; data loss has not been dynamically reproduced.**

At least ten file-backed stores in the reviewed tree use this order: write a temporary JSON file with flush enabled, delete the current canonical file if it exists, then rename the temporary file to the canonical path. Examples include:

- [Project repository](https://github.com/BrainEno/lyric-forge-ktv/blob/e8ea44ee4baa3da1709c9f5a665d0c01926e9e99/lib/features/project/data/repositories/file_project_repository.dart)
- [Batch transcription queue](https://github.com/BrainEno/lyric-forge-ktv/blob/e8ea44ee4baa3da1709c9f5a665d0c01926e9e99/lib/features/transcription/data/services/file_batch_transcription_queue.dart)
- [Local media library](https://github.com/BrainEno/lyric-forge-ktv/blob/e8ea44ee4baa3da1709c9f5a665d0c01926e9e99/lib/features/player/data/repositories/file_local_media_library_repository.dart)
- [Local media collections](https://github.com/BrainEno/lyric-forge-ktv/blob/e8ea44ee4baa3da1709c9f5a665d0c01926e9e99/lib/features/player/data/repositories/file_local_media_collection_repository.dart)
- [Playback session store](https://github.com/BrainEno/lyric-forge-ktv/blob/e8ea44ee4baa3da1709c9f5a665d0c01926e9e99/lib/features/player/data/repositories/file_playback_session_store.dart)
- [Play history repository](https://github.com/BrainEno/lyric-forge-ktv/blob/e8ea44ee4baa3da1709c9f5a665d0c01926e9e99/lib/features/player/data/repositories/file_play_history_repository.dart)
- [Media metadata repository](https://github.com/BrainEno/lyric-forge-ktv/blob/e8ea44ee4baa3da1709c9f5a665d0c01926e9e99/lib/features/player/data/repositories/file_local_media_metadata_repository.dart)
- [Media Hub connection store](https://github.com/BrainEno/lyric-forge-ktv/blob/e8ea44ee4baa3da1709c9f5a665d0c01926e9e99/lib/features/transfer/data/services/file_media_hub_connection_store.dart)
- [Media Hub device identity store](https://github.com/BrainEno/lyric-forge-ktv/blob/e8ea44ee4baa3da1709c9f5a665d0c01926e9e99/lib/features/transfer/data/services/file_media_hub_device_identity_store.dart)
- [Media transfer queue](https://github.com/BrainEno/lyric-forge-ktv/blob/e8ea44ee4baa3da1709c9f5a665d0c01926e9e99/lib/features/transfer/data/services/file_media_transfer_queue_service.dart)

Serializing writes prevents concurrent writers from colliding with each other, and a temporary file reduces the chance of exposing partially written JSON. Neither safeguard closes the interval after the canonical file is deleted and before the rename succeeds. Existing load paths do not establish a common recovery contract for stale temporary files.

**Required action**

1. Inventory all file-backed stores and centralize a replacement primitive with documented Windows/macOS semantics. Preserve the last valid snapshot or implement a same-filesystem replacement strategy that does not delete the old canonical file before the new one can safely take its place.
2. Add recovery rules for canonical, backup, and stale temporary files; validate schema/version/checksum before selecting a candidate. A malformed or missing canonical file must not silently become an empty store followed by a destructive save.
3. Add fault-injection tests at temp write, flush, replacement, and recovery boundaries. Test replacement failures as well as process interruption; retain the previous valid version whenever possible.
4. Treat SQLite as a possible medium-term transaction solution for related project/index records, not as a prerequisite for fixing independent JSON stores.

**Acceptance:** on Windows and macOS, repeated injected failures leave a recoverable valid old or new state; tests demonstrate no successful-write path deletes the only valid copy before replacement succeeds. Do not claim cross-platform atomicity until the exact implementation semantics are verified.

### P1 — Define the Media Hub threat model and enforce upload resource budgets

**Status: confirmed missing limits/secure transport protections; exploitability depends on network reachability and possession of a session token.**

The service binds an HTTP listener to InternetAddress.anyIPv4; authentication accepts a session token in the query string as well as a Bearer header, and the remote playback adapter constructs URLs that include the token. This is not an unauthenticated open file server, but LAN HTTP does not encrypt audio or credentials in transit, and query-string credentials can leak through copied URLs, diagnostics, or history.

The audio upload path streams the request into a .part file and checks the final received byte count against Content-Length when one exists. It does not enforce an absolute byte ceiling when the length is missing, per-upload idle/total timeouts, free-space thresholds, or explicit global/per-device concurrency. Multiple requests are handled asynchronously. Destination selection checks whether a candidate or .part file exists before later creating the .part path, so simultaneous uploads using the same name can race.

**Required action**

1. Set a threat model explicitly: trusted home LAN, Tailscale-only, or untrusted shared LAN. Keep sharing opt-in, display reachable interfaces, and explain that a bearer token on plain LAN HTTP is not encrypted.
2. Enforce a maximum accepted upload size both from Content-Length and by counting actual chunks; abort over-limit streams with a stable 413 response, close resources, and remove only that upload's temporary file.
3. Add idle/overall upload timeouts, a free-disk safety margin, bounded global and per-session concurrency, and back-pressure-aware writes.
4. Use a unique per-upload temporary filename (such as a UUID), allocate final names safely at commit time, and never delete a different session's partial upload. Add concurrent same-name tests using different file contents and verify hashes.
5. Prefer Authorization headers where clients support them. If media frameworks require URL tokens, use short-lived scoped URLs, redact them from logs and error details, and document their lifetime. Evaluate TLS/certificate pinning for untrusted LAN use rather than disabling certificate validation.
6. Keep the existing Range/token protections; expand tests for expired/stale sessions, stop-sharing invalidation, missing/wrong tokens, malformed ranges, empty files, missing source files, uploads, and listener shutdown.

**Acceptance:** a slow, oversized, or concurrent upload cannot write without bound or delete another upload's temporary data; unauthorized requests cannot enumerate or stream content; the user can see and stop the active share; supported Release packaging is tested end to end.

Evidence: [Media Hub listener/upload/auth code at the fixed commit](https://github.com/BrainEno/lyric-forge-ktv/blob/e8ea44ee4baa3da1709c9f5a665d0c01926e9e99/lib/features/transfer/data/services/http_media_hub_service.dart) · [remote playback token URL construction](https://github.com/BrainEno/lyric-forge-ktv/blob/e8ea44ee4baa3da1709c9f5a665d0c01926e9e99/lib/features/transfer/data/services/media_hub_rebinding_audio_player_service.dart).

### P1 — Pin and verify the FFmpeg artifacts the application installs

**Status: confirmed reproducibility/integrity gap in the managed FFmpeg install path.**

The reviewed code downloads Windows FFmpeg from a floating releases/download/latest/ffmpeg-master-latest-win64-lgpl.zip URL and macOS FFmpeg from a getrelease/zip endpoint. It extracts the archive and runs ffmpeg -version, but does not compare the archive against a trusted, release-pinned SHA-256 before extraction. That confirms the executable runs; it does not confirm that the downloaded bytes match the intended release. The separate FFmpeg path is weaker than the repository's more explicit model/runtime integrity handling.

**Required action**

1. Replace floating download endpoints with per-platform release metadata: fixed version/revision, exact URL, expected archive digest, source/build provenance, and any required third-party notices.
2. Verify the downloaded archive hash before extraction; fail closed and preserve the previous working installation if verification or smoke checks fail.
3. Record the installed FFmpeg version, binary digest and build configuration in diagnostics. Keep user-supplied executables supported, but distinguish verified managed binaries from arbitrary paths.

**Acceptance:** a modified archive fails verification before extraction/activation; an interrupted or invalid update cannot erase the previously working FFmpeg install. A -version check alone is not the integrity gate.

Evidence: [managed FFmpeg installer](https://github.com/BrainEno/lyric-forge-ktv/blob/e8ea44ee4baa3da1709c9f5a665d0c01926e9e99/lib/features/transcription/data/services/managed_asr_runtime_manager.dart) · [BtbN documents the floating “latest” build alias](https://github.com/BtbN/FFmpeg-Builds).

### P1 — Make the separation requirement and release scope explicit

**Status: confirmed implementation gap if the current PRD is still the binding product contract.**

The PRD calls desktop vocal/accompaniment separation mandatory and describes the core flow as import → separate → transcribe → editable lyrics. In the reviewed code, AudioAsset can store optional vocalPath and instrumentalPath, and transcription prefers an existing vocal path, but the corresponding workflow falls back to normalized/original audio; the reviewed snapshot does not contain an integrated separation engine that produces those stems. A data field and a vocalsSeparated enum do not implement separation.

**Required action**

1. Decide whether vocal/accompaniment separation remains a release-blocking MVP requirement or whether the first distributable product explicitly supports user-supplied stems/伴奏 only.
2. If the PRD remains unchanged, treat separation as a required product milestone. Start by prototyping candidate backends locally and compare actual separation quality, memory/VRAM requirements, cancellation, progress, resumability, outputs and cache identity. Check model/weight redistribution terms when choosing an artifact to bundle, not before starting local evaluation.
3. Evaluate Demucs or alternatives on actual separation quality, hardware/memory use, cancellation, progress, and output integrity. The upstream repository is archived, so do not assume it is the best technical fit. Check model/weight redistribution terms when selecting an artifact for bundling; that check should not prevent local prototypes or quality comparisons.
4. Keep mobile separation out of scope unless product requirements change; the desktop pipeline should produce and persist stems that can be previewed and reused.

**Acceptance:** the app never reports separation complete before usable stems exist; outputs are linked to the correct source/project and can be regenerated safely. Product copy, README and PRD agree on whether separation is included.

Evidence: [PRD at the fixed commit](https://github.com/BrainEno/lyric-forge-ktv/blob/e8ea44ee4baa3da1709c9f5a665d0c01926e9e99/docs/prd.md) · [audio asset model](https://github.com/BrainEno/lyric-forge-ktv/blob/e8ea44ee4baa3da1709c9f5a665d0c01926e9e99/lib/features/project/domain/models/audio_asset.dart) · [upstream Demucs repository (archived)](https://github.com/facebookresearch/demucs).

### P1 — Deliver installable application artifacts with stable upgrade behavior

**Status: confirmed distribution gap in the reviewed snapshot.**

The repository's GitHub Releases contain ASR runtime ZIPs, not a user-facing Windows/macOS/Android application package. The build workflow publishes the managed runtime bundle only. Android's release build type points at the debug signing configuration and keeps the placeholder com.example.lyric_forge_ktv application ID. This is acceptable for local development/testing, not a durable release identity.

**Required action**

1. Add a reproducible packaging workflow for the platforms actually supported and smoke-tested: start with Windows portable ZIP and Android APK; add macOS package only after Release entitlements and a packaged app pass the Media Hub/permissions tests. Keep unsigned/ad-hoc macOS constraints explicit if paid notarisation is outside budget.
2. Configure an independent Android release key, kept outside the repository and provided via local/CI secrets. Fail the release build if production signing is requested but the key is absent; never fall back silently to the debug key.
3. Decide the stable Android application ID before distributing a public build; verify installation and upgrade with the same signing identity and user-data preservation.
4. Attach checksums, runtime compatibility metadata, required third-party notices, and platform/resource requirements to each release. Publish application artifacts separately from native ASR runtime bundles.

**Acceptance:** a clean release workflow produces a downloadable app artifact for each claimed platform, verifies signatures/checksums, and documents install/upgrade limitations. Do not advertise a platform on the basis of a runtime ZIP or a local developer script alone.

Evidence: [release build configuration](https://github.com/BrainEno/lyric-forge-ktv/blob/e8ea44ee4baa3da1709c9f5a665d0c01926e9e99/android/app/build.gradle.kts) · [runtime-only release workflow](https://github.com/BrainEno/lyric-forge-ktv/blob/e8ea44ee4baa3da1709c9f5a665d0c01926e9e99/.github/workflows/build-asr-runtime.yml) · [Flutter Android release-signing guidance](https://docs.flutter.dev/deployment/android).

### P1 — Turn audio quality from an assertion into a repeatable gate

**Status: existing evaluation tooling; real-song quality baseline remains an evidence gap.**

The repository already has transcript, forced-alignment and preprocessing A/B evaluators. Do not rewrite these tools or say no evaluation infrastructure exists. The missing piece is a clearly documented, provenance-matched reference corpus and a baseline report that proves what the deployed engine configuration does on representative songs. Synthetic unit tests can validate metric implementations but cannot prove lyric recall or timestamp accuracy.

**Required action**

1. Start with 10–20 legally testable songs in a private/local corpus: Chinese, English, mixed-language, repeated chorus, fast singing, weak vocals, long instrumental gaps, and tracks with/without a vocal stem. Expand the corpus after the harness is stable.
2. Freeze source-audio SHA-256, manually reviewed reference text/timestamps, model revision, runtime revision, engine order, preprocessing and platform/hardware for each comparison.
3. Report CER and applicable-language WER, omitted/repeated lines, line-boundary errors, human correction time, runtime/real-time factor and peak memory. Keep failures visible and stratify by language/condition.
4. Require an evaluation delta for quality-relevant ASR, alignment and preprocessing changes. A self-hosted runner can be optional; never upload private user music to a public runner/dashboard. Keep restricted audio/reference assets local when necessary; publish aggregate metrics and methodology without redistributing those assets.

**Acceptance:** changes to the quality pipeline can be compared with the prior baseline using identical inputs/configuration, and the report includes regressions and failure samples rather than only one overall average.

Evidence: [ASR quality boundary](https://github.com/BrainEno/lyric-forge-ktv/blob/e8ea44ee4baa3da1709c9f5a665d0c01926e9e99/docs/high_quality_asr.md) · [paired preprocessing evaluator](https://github.com/BrainEno/lyric-forge-ktv/blob/e8ea44ee4baa3da1709c9f5a665d0c01926e9e99/tool/asr_preprocessing_ab_eval.dart) · [transcript evaluator](https://github.com/BrainEno/lyric-forge-ktv/blob/e8ea44ee4baa3da1709c9f5a665d0c01926e9e99/tool/asr_transcript_eval.dart).

### P1 — Validate exported mix peaks before claiming clipping protection

**Status: confirmed risk in the mix filter; audible clipping has not been measured.**

The mix builder allows voice gain up to 2.0 and backing gain up to 1.0, uses amix with normalize=0, and exports signed 16-bit PCM without a limiter in that filter chain. This can exceed full scale when high-level samples add together, but static inspection alone does not establish that the current recordings clip in practice.

**Required action**

1. Add an actual FFmpeg-rendered regression fixture: near-full-scale backing plus voice signals in phase, out of phase, and with transients.
2. Measure decoded output peak and count full-scale/clipped samples; record duration and inter-track alignment as well as peak levels.
3. Define a safe default headroom and, if measurements require it, adopt a limiter or explicit normalization policy that does not silently shift timing or remove the original stems.
4. Keep original vocal and backing stems; make destructive peak processing reproducible and explicit.

**Acceptance:** tests measure actual rendered samples rather than only matching filter-argument strings. The default export meets the agreed peak budget on worst-case fixtures without damaging duration/alignment.

Evidence: [KTV mix filter builder](https://github.com/BrainEno/lyric-forge-ktv/blob/e8ea44ee4baa3da1709c9f5a665d0c01926e9e99/lib/features/player/data/services/local_ktv_recording_service.dart) · [current export argument test](https://github.com/BrainEno/lyric-forge-ktv/blob/e8ea44ee4baa3da1709c9f5a665d0c01926e9e99/test/features/player/ktv_recording_export_test.dart).

### P2 — Improve core-screen testability, runtime coverage and maintenance documentation incrementally

**Do not adopt broad framework or CI rewrites just because of counts or line length.**

The fixed snapshot contains very large editor/player screens and a hand-written app-wide ServiceLocator; the managed runtime build currently publishes Windows x64 CUDA (compiled for sm_120) and macOS x64 artifacts, not a full Linux/Apple-Silicon/CUDA-generation matrix. The README still begins with Flutter template text, points to ./Scripts/ios-dev while the tree contains scripts/ios_build.sh/repair helpers instead, and does not clearly state the downloadable-artifact and platform support matrix.

**Required action**

1. Before decomposing editor/player screens, add focused widget tests for core user actions (open project, edit/save lyric, apply/revert alignment, play/seek, export/error states). Then extract controller/state and visual sections one workflow at a time, preserving existing domain contracts.
2. Track for each managed runtime: supported OS/architecture, accelerator, model, required memory/disk, downloadable artifact, and last real-hardware validation. Treat sm_80/86/89/120, Apple Silicon and Linux as candidate targets, not proven supported targets; compilation on a generic CI runner does not replace device validation.
3. Add a pin ledger for flutter_soloud, file_picker, and the local just_audio_media_kit fork: current version/upstream commit, reason for pin/fork, specific regression it prevents, and next review trigger. Contribute safe changes upstream where practical.
4. Rewrite README as a user-facing entry point: what works today, what needs local FFmpeg/models, download sizes, install/upgrade instructions, tested hardware/platform matrix, limitations, and correct paths. State clearly that Web is unsupported if that remains true.
5. Consider zh/en localization as an adoption milestone, not a release-security blocker. Any crash diagnostics/telemetry must be opt-in, explain what leaves the device, and preserve the local-first promise.
6. Do not merge/delete regression-guard workflows solely to reduce the workflow count. First measure CI wall time, duplicated setup and maintenance cost; consolidate only when the same test contracts and failure visibility remain.

**Acceptance:** core flows have regression tests before refactors; each advertised runtime target has a corresponding validation record; a clean checkout can follow README paths that actually exist; dependency pins and fork deltas are reviewable.

Evidence: [build runtime workflow](https://github.com/BrainEno/lyric-forge-ktv/blob/e8ea44ee4baa3da1709c9f5a665d0c01926e9e99/.github/workflows/build-asr-runtime.yml) · [README](https://github.com/BrainEno/lyric-forge-ktv/blob/e8ea44ee4baa3da1709c9f5a665d0c01926e9e99/README.md) · [service locator](https://github.com/BrainEno/lyric-forge-ktv/blob/e8ea44ee4baa3da1709c9f5a665d0c01926e9e99/lib/core/services/service_locator.dart).

### Review claims deliberately not accepted as written

- **SoLoud licence:** the report's “GPL” claim is not supported by the package/source checked. flutter_soloud 4.1.7 publishes an MIT licence; the underlying SoLoud engine documents ZLib/LibPNG licensing. Keep these separate in the SBOM and validate the exact distributed dependency tree instead of registering a false GPL blocker. [flutter_soloud 4.1.7 licence](https://pub.dev/packages/flutter_soloud/license) · [SoLoud legal information](https://solhsa.com/soloud/legal.html).
- **Demucs integration:** the archived upstream repository is a maintenance and technical-fit consideration. Evaluate real separation quality and runtime cost first; review artifact redistribution terms when a specific model/weight bundle is chosen, rather than making speculative license analysis a blocker for local prototyping. [official Demucs repository](https://github.com/facebookresearch/demucs).
- **No tests / no reliability controls:** too broad. The project already has extensive tests for recovery, locks, WAV storage, transcription, runtime readiness and Media Hub paths. The actionable gaps are specific coverage for UI workflows, failure windows, upload resource limits, real-song quality, and actual audio output—not a wholesale dismissal of existing tests.
- **CI workflow count:** workflow count alone does not prove that CI is unmaintainable. Measure run time and duplicated work before consolidation.
- **Telemetry:** absence of default telemetry is not automatically a defect for a local-first music tool; any future operational diagnostics must be optional and privacy-preserving.

## Updated implementation order after the second review

1. Close the confirmed delete-before-rename persistence window and add failure/recovery tests; also assert the macOS Release incoming-network entitlement before claiming packaged Media Hub support.
2. Add ASR process timeout/cancellation lifecycle tests so a stuck child process cannot block an unattended job forever.
3. Harden Media Hub upload byte/time/concurrency limits and same-name file allocation; document LAN/Tailscale security boundaries and token lifetime.
4. Pin and hash managed FFmpeg artifacts; ensure failed upgrades preserve the old working binary.
5. Implement the PRD's desktop vocal/accompaniment separation requirement (or explicitly amend the product scope) and build/install/test actual application packages with stable app identity and safe upgrade behavior.
6. Establish a provenance-matched real-song baseline and rendered-mix peak/clipping tests.
7. Track runtime source revisions, binary hashes and required third-party notices for the specific artifacts that will actually be bundled. Keep this as a scoped packaging task; it must not block local evaluation, feature work, or unrelated reliability fixes.
8. Expand runtime targets based on real hardware validation, then incrementally add core-screen tests, improve README, and maintain the dependency pin/fork ledger.

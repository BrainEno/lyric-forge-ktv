# Engineering Review Findings and Deferred-Risk Roadmap

> Review date: 2026-10-28. Scope: verify findings against the current `main` source, not accept model-generated review summaries at face value.
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
- **Atomic JSON writes:** temp-file-and-rename patterns and serialized writes are real safeguards. Keep them, and strengthen failure/recovery tests where needed.
- **Two audio engines, JSON storage, or CLI processes by themselves:** these are not sufficient reasons for a broad rewrite. Prioritize reproducible failure modes and measured performance/quality before choosing a new architecture.

## Suggested order

1. Fix and CI-gate the Release network-server entitlement before a macOS Media Hub release.
2. Add process timeout/cancellation lifecycle tests for the ASR CLI adapter.
3. Establish JSON repository scale benchmarks; decide on SQLite/indexing only from measured results.
4. Run audio latency/alignment/drift measurements on representative hardware.
5. Expand Media Hub token and Range boundary tests, including Release packaging and listener shutdown.

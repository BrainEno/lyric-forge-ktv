# [2026-12-25 09:30] Sung-language probe before recognition

- Scope: round 41, user report: an English song by The Doors was recognised as Norwegian and the draft had two words (D-061).
  - Root cause in whisper.cpp (`927cfce`): with `-l auto`, `whisper_full_with_state` detects the language once at mel offset 0, so only the first 30 s of the input count (`--offset-t` does not move it). An instrumental intro, or a separated vocal stem that is silent until the verse, gives `nn` and the whole song is decoded in it.
  - `SpokenLanguagePolicy` / `SpokenLanguageResolution` (domain): picks the 10 s windows with the most singing (vocal activity on a clean stem, loudness on a mix; near-silence is skipped), up to 3 per probe and 2 probes; decides from a reliable probe (p >= 0.5, >= 0.9 for hallucination-prone codes such as `nn`, `cy`, `la`), then the song title/artist script or English words, then a probe with p >= 0.25, else unresolved. Stored under `transcription.spokenLanguage`.
  - `WhisperSpokenLanguageDetector` (data): FFmpeg to 16 kHz mono WAV, energy envelope, `writePcmWavClip` joins the windows, `whisper-cli -l auto --detect-language`, parses `auto-detected language: xx (p = ...)` from stderr; retries without the flag for an old CLI; never fails the run; cancellable.
  - `LocalProjectTranscriptionWorkflow` probes only when the config language is auto and pins the found language for recognition and gap filling; progress shows 正在判断演唱语言 / 演唱语言：英文. `ProjectSpanRecognitionService` and `IndependentProjectRerunService` reuse the project's language (`SpokenLanguageResolution.languageOfProject`, falling back to a usable `detectedLanguage`).
- Files:
  - New: `lib/features/transcription/domain/models/spoken_language.dart`, `lib/features/transcription/domain/services/spoken_language_detector.dart`, `lib/features/transcription/data/services/{whisper_spoken_language_detector,pcm_wav_clip_writer}.dart`, `test/features/transcription/spoken_language/{spoken_language_policy_test,whisper_spoken_language_detector_test}.dart`.
  - Changed: `lib/features/transcription/data/services/{local_project_transcription_workflow,project_span_recognition_service,independent_project_rerun_service}.dart`, `lib/app/app_services.dart`, `test/features/transcription/vocal_gap_fill/workflow_vocal_gap_fill_test.dart`.
  - `docs/decisions.md` (D-061), `docs/handoff.md`.
- Validation:
  - No Dart SDK in the sandbox: format, analyze and tests => PR's Flutter Quality Gate.
- Notes:
  - A language chosen in the recognition settings is never probed or changed.
  - Chunked runs (over 20 min) fingerprint the language, so a pinned language starts such a run afresh instead of resuming an `auto` one.
- Commit: `Detect the sung language from the vocal parts before recognition`

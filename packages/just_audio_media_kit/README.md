# LyricForge vendored just_audio_media_kit

## Provenance

This directory is a local fork of upstream
[`just_audio_media_kit` v2.1.0](https://github.com/Pato05/just_audio_media_kit/tree/f55b491082b7c4071b2cc102b7e0308a9f9c7111),
tag `v2.1.0`, commit `f55b491082b7c4071b2cc102b7e0308a9f9c7111`.
On 2026-11-07, a comparison against that tag showed an identical `pubspec.yaml`
and `LICENSE`; before the testability extraction below, only
`lib/mediakit_player.dart` differed among the upstream `lib` files. The upstream
file's SHA-256 is
`6e63a855ac12941e80d98edb6a109693c2709d283d889b608f9283af95b50033`.
The upstream package's other files, including its example, are not vendored.

## Local changes

- After player readiness, set MPV `cache-on-disk=no`, avoiding the optional
  temporary packet-cache file while leaving memory/network buffering enabled.
- Set `sub-auto=no` before opening media so MPV does not load adjacent lyric
  files as subtitles; the app handles lyrics itself.
- Set `PlayerConfiguration.osc=true`. In the app's locked `media_kit` 1.2.6,
  this avoids its attempted `osc=no` runtime property write, which some
  audio-only libmpv builds reject. This adapter has no video surface; this is
  not a general recommendation to enable controls in other applications.
- `lib/src/audio_player_setup.dart` factors the same configuration and ordered
  readiness options into testable helpers; no intended playback behavior changes.

The parent app uses this directory as a path dependency and resolves it through
the **root** `pubspec.lock`, not a separately resolved package lockfile. The
root analyzer exclusion remains in place; exclusion is not a quality guarantee.

## Updating and validation

1. Select and record the exact upstream tag and immutable commit, compare its
   `lib`, `pubspec.yaml` and `LICENSE` with this directory, and review upstream
   changes/security fixes before applying them. Preserve license/provenance and
   explain each remaining local delta; do not silently overwrite these patches.
2. Reassess whether each workaround is still required for the target MPV and
   locked `media_kit` versions. Update the helper tests and this record when
   behavior or dependencies change; use the root lockfile and pinned `.fvmrc`.
3. From the repository root run `flutter pub get --enforce-lockfile`, then
   `flutter test --no-pub packages/just_audio_media_kit/test` and
   `bash scripts/quality_gate.sh --skip-pub-get`. The universal Flutter Quality
   Gate explicitly runs the nested package tests on every PR and main push.
4. On actual Windows and Linux builds, smoke-test local and network playback,
   seeking, pause/resume and restart, including a neighboring `.lrc` file and a
   restricted/unwritable cache location. Inspect MPV logs and first-play
   behavior. The unit tests use injected property writers and do **not** launch
   libmpv, verify the actual native options, or replace physical playback tests.

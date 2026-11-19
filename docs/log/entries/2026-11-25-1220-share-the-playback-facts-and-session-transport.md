# [2026-11-25 12:20] Share the playback facts and session transport

- Scope: UI/UX audit, player family ("与 QuickPlay 的 _Transport、_InfoChip 同名私有类重复实现", P2). Now Playing and quick play each kept a private `_InfoChip` and a private wrapper that wired `TransportBar` to the playback session (`_TransportControls`, `_Transport`). The badges disagreed: Now Playing showed `MP3`, `LOCAL`/`REMOTE`/`PROJECT` and `LYRICS`; quick play showed `MP3` (or `AUDIO`), `已有歌词`/`未添加歌词` and `LOCAL`. The origin badge repeated the page title or the origin line above the title, and the English words broke the Chinese interface (AGENTS.md). The new `PlaybackFactBadges` shows the format and the lyrics status in the same words on both pages (lyrics present is a success badge with a lyrics icon; missing lyrics is a plain badge that Now Playing leaves out), and `PlaybackOrigin` replaces Now Playing's record-returning `_sourcePresentation`. The new `SessionTransportBar` replaces both transport wrappers; it takes an optional queue snapshot so Now Playing keeps reading its session stream. Quick play no longer threads a separate `format` string through three widgets.
- Files:
  - `lib/features/player/presentation/widgets/playback_facts.dart` (new: `PlaybackOrigin`, `PlaybackFactBadges`).
  - `lib/features/player/presentation/widgets/session_transport_bar.dart` (new).
  - `lib/features/player/presentation/screens/now_playing_screen.dart`.
  - `lib/features/player/presentation/screens/quick_play_screen.dart`.
  - `test/features/player/presentation/widgets/playback_facts_test.dart` (new: origin precedence and labels; format label capitals, dot and fallback; lyrics badges and tones; no English origin words).
  - `test/features/player/presentation/widgets/session_transport_bar_test.dart` (new: buttons drive the session; skip buttons follow the queue; a snapshot wins over the session state; pause while playing; busy states; seek buttons).
- Validation:
  - No Dart/Flutter toolchain in the sandbox; `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate and the temporary format probe.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - The project player's `_TransportPane`/`_PlaybackControls` split and the immersive KTV controls are separate audit items and stay as they are.
- Commit: `Share the playback facts and session transport`

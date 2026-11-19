# [2026-11-24 12:10] Fold track imports on the project page

- Scope: UI/UX audit P-02. The project page's action panel showed 导入已有伴奏 / 更换伴奏 and 导入已有人声 / 更换人声 as two full-width buttons right below 校对歌词 and 打开播放器, giving a rarely used audio-engineering step the same weight as the main path. They now sit behind one 伴奏与人声 row that says which tracks the project has (e.g. 已有伴奏轨 · 没有人声轨) and opens the buttons on demand. The row is announced as an expandable button, is 48 dp on touch layouts, and stays open (and locked) while an import runs so the progress label stays visible. Labels, confirmation dialogs, SnackBars and the alignment footnote are unchanged.
- Files:
  - `lib/features/project/presentation/widgets/project_audio_sources_section.dart` (new: `ProjectAudioSourcesSection`, `audioSourcesSummary`).
  - `lib/features/project/presentation/screens/project_detail_screen.dart` (`_audioSourcesExpanded` in the screen state, passed through `_ProjectDetailContent` and `_ActionPanel`; the stem buttons are replaced by the section).
  - Tests: `test/features/project/presentation/project_audio_sources_section_test.dart` (new: collapsed row, callbacks, replacement labels, running import keeps it open and locked, recognition disables imports, expanded semantics, summary), `test/features/project/presentation/project_detail_capability_test.dart` (`_showProject` opens the section by default; `_reveal` centres a target before taps that follow a reload; new cases: folded by default with the main action still first, open state survives the refresh after an import; mobile shows no section).
- Validation:
  - No Dart/Flutter toolchain in the sandbox, so `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - The open state lives in the screen state because a refresh after an import shows the loading state and rebuilds the whole page.
  - The summary avoids the words of the 伴奏已导入 / 人声已导入 SnackBars so existing `textContaining` checks still find exactly one match.
- Commit: `Fold track imports on the project page`

# [2026-12-05 09:30] Split the speech recognition setup dialog

- Scope: I-03 from the audit, the last open row of `issues.md`. The first-run setup of local lyric recognition (`asr_runtime_setup_dialog.dart`) was one 957-line file:
  - one State object with fourteen fields of progress and error state;
  - about 420 lines of flows (inspect, space check, install, pause and resume, scan for an earlier download, adopt a pasted or picked folder, move the managed folder, advanced settings);
  - a 200-line build method with its sentences inline;
  - five private cards at the end.

  The same guard (`_loading || _installing || _scanningExisting || isInstalling`) was written out three times, and the two install-failure branches were copies of each other. It is now split the way the settings page was split in C-03 (D-039):
  - `asr_runtime_setup_controller.dart`: `AsrRuntimeSetupController`, a `ChangeNotifier` that holds the state and runs the flows. It checks `isDisposed` after every await, so a dialog closed during an inspection or scan is no longer notified. The guards are named (`canUseExisting`, `canMoveStorage`, `canChangeMode`, `canClose`), and the buttons come from `actionsFor` and `isEnabled` instead of an if/else chain in the action list. The two failure branches share `_installFailed`.
  - `asr_runtime_setup_cards.dart`: the header, numbered steps, mode menu, profile card, components card and row, hint and one `AsrSetupActionButton` per action. All of them are public and stateless.
  - `asr_runtime_setup_text.dart`: `AsrSetupText`, every sentence of the dialog, including the shortfall, the "adopted an existing environment" variants and the move snack bar.
  - `asr_runtime_setup_dialog.dart` (248 lines) keeps the public `AsrRuntimeSetupDialog(dependencies:)` and what needs a `BuildContext`: the folder pickers, the path dialog, the advanced settings dialog, the snack bar and the pops.

  Accessibility fixes made along the way:
  - The header title and each step are headings.
  - A step reads as 「第 1 步，选择识别方案…」 instead of a bare 「1」.
  - A component row is one stop (「FFmpeg，已准备，系统已安装」) instead of four.
  - A component that is `installing` or `failed` explicitly reads 待准备, as the old else-branch did.
- Files:
  - New: `lib/features/transcription/presentation/widgets/asr_runtime_setup_controller.dart`, `asr_runtime_setup_cards.dart`, `asr_runtime_setup_text.dart`.
  - `lib/features/transcription/presentation/widgets/asr_runtime_setup_dialog.dart`.
  - New tests: `test/features/transcription/presentation/asr_runtime_setup_controller_test.dart`, `asr_runtime_setup_text_test.dart`, `asr_runtime_setup_dialog_test.dart`, and the shared fakes `asr_setup_fakes.dart`.
  - Contract tests now read the dialog, cards, controller and text together: `test/features/transcription/asr_install_experience_contract_test.dart`, `asr_managed_storage_contract_test.dart`, `asr_storage_preflight_contract_test.dart`.
  - `docs/decisions.md` (D-039), `artifacts/ui-audit/reports/issues.md` (I-03 handled; status section for round 18).
- Validation:
  - Controller unit tests:
    - inspection, including both failure messages and clearing an error;
    - progress from the runtime; the quality mode, including no change while downloading;
    - install success, the checking-existing first step, the full-disk stop with its numbers;
    - pause, resume keeping progress, a failure naming its component, the generic retry;
    - scanning (not found, ready, partial, failed, blocked while the runtime downloads), pasted paths (adopted, blank, not recognised);
    - moving the folder (moved, onto an existing environment, nothing changed, failed, blocked);
    - advanced settings (saved, not saved when incomplete, failed save keeps the old plan);
    - the action matrix and enabled states; nothing is notified after dispose.
  - Unit tests for every sentence in `AsrSetupText`.
  - Widget tests for each card (headings, step label, mode menu, profile, components and the spoken row, hint, every button label, the blocked install).
  - Dialog widget tests: first-run layout; install then 开始使用 pops with the installed plan; a full disk disables the button; back is blocked while downloading, then pause, 以后继续 pops with nothing; the mode menu inspects again; a failure offers 重试 Whisper 模型; a 390-wide phone does not overflow.
  - The source contracts keep every literal they asked for, and the save → apply → refresh order of the advanced settings.
  - The importers still import only `asr_runtime_setup_dialog.dart`, so the presentation import baseline is unchanged.
  - Format, analyze and tests => PR's Flutter Quality Gate and the temporary probe workflow.
- Notes:
  - Not looked at in a running app. The layout and wording are unchanged apart from the screen-reader labels above.
  - Unlike the settings controller, this one does not save the plan after an install, because the caller receives it when the user taps 开始使用. That behaviour is kept.
  - The existing-model buttons are still greyed out by loading, installing and scanning only. Whether the runtime downloads elsewhere is checked when tapped, because it is not something the dialog can listen to.
- Commit: `Split the speech recognition setup dialog into controller, cards and text`

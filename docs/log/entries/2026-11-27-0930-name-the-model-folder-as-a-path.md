# [2026-11-27 09:30] Name the model folder as a path

- Scope: B-02 follow-up after the user confirmed their models live in `D:\Models\LyricForge\ASRRuntime`. Storage already recognised that layout (candidates under drive roots and `Models/LyricForge/ASRRuntime`, bounded discovery, pasted paths), so the fix is the copy: the interface wrote "LyricForge ASRRuntime" as if it were a product name and "已有的 ASRRuntime" without saying where. New `AsrFolderText` spells the folder as a path with the platform separator (`LyricForge\ASRRuntime` on Windows, `LyricForge/ASRRuntime` elsewhere), gives a full example (`D:\Models\LyricForge\ASRRuntime`, `/Volumes/Data/Models/…`, `/mnt/data/Models/…`) in the card, the paste dialog and the "not found" message, and renames "浏览已有 ASRRuntime" / "粘贴已有 ASRRuntime 路径" to "浏览模型文件夹" / "粘贴已有模型文件夹的路径". The setup dialog and the settings page kept separate copies of each message; both read them from `AsrFolderText` now.
- Files:
  - `lib/features/transcription/presentation/asr_folder_text.dart` (new).
  - `lib/features/transcription/presentation/widgets/asr_existing_model_actions.dart`, `asr_runtime_setup_dialog.dart`.
  - `lib/features/settings/presentation/widgets/ai_transcription_settings_section.dart`.
  - `lib/features/transcription/data/services/local_asr_managed_storage_service.dart` (macOS hint names the renamed button).
  - `test/features/transcription/presentation/asr_folder_text_test.dart` (new: Windows/macOS/Linux paths and hints, every message names the folder, no-download promises, card and paste dialog with the Windows example, trimmed result, cancel).
  - `test/features/transcription/asr_managed_storage_contract_test.dart`.
- Validation:
  - No Dart/Flutter toolchain in the sandbox; `dart format`, `flutter analyze` and the tests run in the PR's Flutter Quality Gate and a temporary probe workflow.
  - Work-log `write` + `check` => Python port of `tool/work_log.dart`.
- Notes:
  - The on-disk layout and the storage error "目标位置已经存在 LyricForge ASRRuntime 数据" are unchanged; only presentation copy moved.
- Commit: `Name the model folder as a path`

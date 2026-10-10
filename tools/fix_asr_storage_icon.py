from pathlib import Path

for raw in [
    'lib/features/settings/presentation/widgets/ai_transcription_settings_section.dart',
    'lib/features/transcription/presentation/widgets/asr_storage_preflight_card.dart',
]:
    path = Path(raw)
    text = path.read_text(encoding='utf-8')
    old = 'Icons.drive_file_move_outline_rounded'
    if text.count(old) != 1:
        raise RuntimeError(f'{raw}: expected one unsupported icon, found {text.count(old)}')
    path.write_text(text.replace(old, 'Icons.folder_open_rounded'), encoding='utf-8')

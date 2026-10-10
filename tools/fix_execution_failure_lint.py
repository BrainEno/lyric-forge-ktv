from pathlib import Path

path = Path('lib/features/transcription/data/services/resumable_chunked_transcription_service.dart')
text = path.read_text(encoding='utf-8')
old = "manifest!['completed']"
new = "manifest['completed']"
if text.count(old) != 1:
    raise RuntimeError(f'expected exactly one {old!r}, found {text.count(old)}')
path.write_text(text.replace(old, new), encoding='utf-8')

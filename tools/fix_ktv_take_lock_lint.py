from pathlib import Path
path = Path('lib/features/player/presentation/screens/player_screen.dart')
text = path.read_text(encoding='utf-8')
old = 'Image.file(file!, fit: BoxFit.cover)'
new = 'Image.file(file, fit: BoxFit.cover)'
if text.count(old) != 1:
    raise RuntimeError(f'expected one redundant assertion, found {text.count(old)}')
path.write_text(text.replace(old, new), encoding='utf-8')

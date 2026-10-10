from pathlib import Path

path = Path('lib/features/transcription/data/services/managed_model_asr_runtime_manager.dart')
text = path.read_text(encoding='utf-8')
old = "'正在下载 ${_modelLabel(modelId)} · ${index + 1}/${files.length}',"
new = "'正在下载 ${_modelLabel(modelId)} · ${index + 1}/${files.length} · ${_percent(modelFraction)}',"
assert text.count(old) == 1
path.write_text(text.replace(old, new, 1), encoding='utf-8')

path = Path('lib/features/settings/presentation/widgets/ai_transcription_settings_section.dart')
text = path.read_text(encoding='utf-8')
old = '  bool get _busy => _loading || _installing || _deleting;'
new = '  bool get _busy => _loading || _installing || _paused || _deleting;'
assert text.count(old) == 1
path.write_text(text.replace(old, new, 1), encoding='utf-8')

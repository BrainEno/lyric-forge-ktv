from pathlib import Path

path = Path('lib/features/player/presentation/screens/player_screen.dart')
text = path.read_text()

old_sources = """                            if (ktvSources.length > 1) ...[
                              IgnorePointer(
                                ignoring: recordingLocked,
                                child: Opacity(
                                  opacity: recordingLocked ? 0.45 : 1,
                                  child: spec.isCompact || spec.isShort
                                      ? _CompactSourceMenu(
                                          availableSources: ktvSources,
                                          currentSource: playback.currentSource,
                                          onSourceChanged: widget.onSwitchSource,
                                          ktvLabels: true,
                                        )
                                      : _AudioSourceSelector(
                                          availableSources: ktvSources,
                                          currentSource: playback.currentSource,
                                          onSourceChanged: widget.onSwitchSource,
                                          compact: true,
                                          ktvLabels: true,
                                        ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                            ],
"""
new_sources = """                            if (ktvSources.length > 1) ...[
                              if (spec.isCompact || spec.isShort)
                                IgnorePointer(
                                  ignoring: recordingLocked,
                                  child: Opacity(
                                    opacity: recordingLocked ? 0.45 : 1,
                                    child: _CompactSourceMenu(
                                      availableSources: ktvSources,
                                      currentSource: playback.currentSource,
                                      onSourceChanged: widget.onSwitchSource,
                                      ktvLabels: true,
                                    ),
                                  ),
                                )
                              else
                                Flexible(
                                  child: IgnorePointer(
                                    ignoring: recordingLocked,
                                    child: Opacity(
                                      opacity: recordingLocked ? 0.45 : 1,
                                      child: _AudioSourceSelector(
                                        availableSources: ktvSources,
                                        currentSource: playback.currentSource,
                                        onSourceChanged: widget.onSwitchSource,
                                        compact: true,
                                        ktvLabels: true,
                                      ),
                                    ),
                                  ),
                                ),
                              const SizedBox(width: AppSpacing.sm),
                            ],
"""
if old_sources not in text:
    raise SystemExit('source selector block not found')
text = text.replace(old_sources, new_sources, 1)

old_state = """class _KtvTakeResultSheetState extends State<_KtvTakeResultSheet> {
  late KtvRecordingSession _session;
  bool _exporting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _session = widget.initialSession;
  }
"""
new_state = """class _KtvTakeResultSheetState extends State<_KtvTakeResultSheet> {
  late KtvRecordingSession _session;
  late double _voiceVolume;
  late double _backingVolume;
  bool _exporting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _session = widget.initialSession;
    _voiceVolume = 1.0;
    _backingVolume = _session.backingVolume;
  }
"""
if old_state not in text:
    raise SystemExit('take result state block not found')
text = text.replace(old_state, new_state, 1)

old_export = """      final exported = await widget.recordingService.exportMix(_session);
"""
new_export = """      final exported = await widget.recordingService.exportMix(
        _session,
        voiceVolume: _voiceVolume,
        backingVolume: _backingVolume,
      );
"""
if old_export not in text:
    raise SystemExit('export call not found')
text = text.replace(old_export, new_export, 1)

anchor = """              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                _PlaybackError(message: _error!),
              ],
              const SizedBox(height: AppSpacing.lg),
"""
insert = """              const SizedBox(height: AppSpacing.lg),
              _KtvControlLabel(
                title: '导出人声音量',
                value: '${(_voiceVolume * 100).round()}%',
              ),
              Slider(
                value: _voiceVolume,
                min: 0,
                max: 2,
                divisions: 20,
                onChanged: _exporting
                    ? null
                    : (value) => setState(() => _voiceVolume = value),
              ),
              _KtvControlLabel(
                title: '导出伴奏音量',
                value: '${(_backingVolume * 100).round()}%',
              ),
              Slider(
                value: _backingVolume,
                min: 0,
                max: 1,
                divisions: 20,
                onChanged: _exporting
                    ? null
                    : (value) => setState(() => _backingVolume = value),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                _PlaybackError(message: _error!),
              ],
              const SizedBox(height: AppSpacing.lg),
"""
if anchor not in text:
    raise SystemExit('take result controls anchor not found')
text = text.replace(anchor, insert, 1)

path.write_text(text)

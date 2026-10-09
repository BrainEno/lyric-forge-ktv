from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    target = Path(path)
    text = target.read_text()
    if old not in text:
        raise SystemExit(f"Expected text not found in {path}: {old[:140]!r}")
    target.write_text(text.replace(old, new, 1))


# Expose the raw captured PCM before monitoring gain/delay so recording remains
# a clean, remixable vocal stem.
replace_once(
    "lib/features/player/domain/services/ktv_microphone_service.dart",
    "import '../models/ktv_microphone_state.dart';\n",
    "import 'dart:typed_data';\n\nimport '../models/ktv_microphone_state.dart';\n",
)
replace_once(
    "lib/features/player/domain/services/ktv_microphone_service.dart",
    "  KtvMicrophoneState get currentState;\n\n",
    "  KtvMicrophoneState get currentState;\n  Stream<Uint8List> get rawPcm16Stream;\n\n",
)

mic = Path("lib/features/player/data/services/record_soloud_ktv_microphone_service.dart")
text = mic.read_text()
text = text.replace(
    "  final StreamController<KtvMicrophoneState> _stateController =\n      StreamController<KtvMicrophoneState>.broadcast();\n",
    "  final StreamController<KtvMicrophoneState> _stateController =\n"
    "      StreamController<KtvMicrophoneState>.broadcast();\n"
    "  final StreamController<Uint8List> _rawPcmController =\n"
    "      StreamController<Uint8List>.broadcast(sync: true);\n",
    1,
)
text = text.replace(
    "  @override\n  KtvMicrophoneState get currentState => _state;\n\n",
    "  @override\n  KtvMicrophoneState get currentState => _state;\n\n"
    "  @override\n  Stream<Uint8List> get rawPcm16Stream => _rawPcmController.stream;\n\n",
    1,
)
text = text.replace(
    "  void _handleInputFrame(Uint8List bytes) {\n    if (!_state.isMonitoring || bytes.length < 2) return;\n\n",
    "  void _handleInputFrame(Uint8List bytes) {\n"
    "    if (!_state.isMonitoring || bytes.length < 2) return;\n"
    "    if (!_rawPcmController.isClosed) {\n"
    "      _rawPcmController.add(Uint8List.fromList(bytes));\n"
    "    }\n\n",
    1,
)
text = text.replace(
    "  void _handleInputError(Object error, StackTrace stackTrace) {\n    if (!_state.isMonitoring && !_state.isStarting) return;\n    unawaited(_recoverFromStreamError(error));\n  }\n",
    "  void _handleInputError(Object error, StackTrace stackTrace) {\n"
    "    if (!_state.isMonitoring && !_state.isStarting) return;\n"
    "    if (!_rawPcmController.isClosed) {\n"
    "      _rawPcmController.addError(error, stackTrace);\n"
    "    }\n"
    "    unawaited(_recoverFromStreamError(error));\n"
    "  }\n",
    1,
)
text = text.replace(
    "    if (_initializedSoloud && _soloud.isInitialized) {\n      await _soloud.deinitAsync();\n    }\n    await _stateController.close();\n",
    "    if (_initializedSoloud && _soloud.isInitialized) {\n"
    "      await _soloud.deinitAsync();\n"
    "    }\n"
    "    await _rawPcmController.close();\n"
    "    await _stateController.close();\n",
    1,
)
mic.write_text(text)

# Register the recording orchestrator after the transcription settings store is
# available, so it can reuse the app's configured FFmpeg executable.
replace_once(
    "lib/core/services/service_locator.dart",
    "import '../../features/player/data/services/record_soloud_ktv_microphone_service.dart';\n",
    "import '../../features/player/data/services/record_soloud_ktv_microphone_service.dart';\n"
    "import '../../features/player/data/services/local_ktv_recording_service.dart';\n",
)
replace_once(
    "lib/core/services/service_locator.dart",
    "import '../../features/player/domain/services/ktv_microphone_service.dart';\n",
    "import '../../features/player/domain/services/ktv_microphone_service.dart';\n"
    "import '../../features/player/domain/services/ktv_recording_service.dart';\n",
)
replace_once(
    "lib/core/services/service_locator.dart",
    "  late final KtvMicrophoneService ktvMicrophoneService;\n",
    "  late final KtvMicrophoneService ktvMicrophoneService;\n"
    "  late final KtvRecordingService ktvRecordingService;\n",
)
replace_once(
    "lib/core/services/service_locator.dart",
    "    transcriptionSettingsStore = FileTranscriptionSettingsStore();\n",
    "    transcriptionSettingsStore = FileTranscriptionSettingsStore();\n"
    "    ktvRecordingService = LocalKtvRecordingService(\n"
    "      audioService: audioPlayerService,\n"
    "      microphoneService: ktvMicrophoneService,\n"
    "      settingsStore: transcriptionSettingsStore,\n"
    "    );\n",
)

# Snapshot playback as late as possible, after microphone startup and WAV file
# creation, so the take's backing start position matches the first captured PCM.
recording = Path("lib/features/player/data/services/local_ktv_recording_service.dart")
text = recording.read_text()
old = """    final playback = _audioService.currentState;
    if (!playback.isPlaying || playback.isBuffering || playback.isLoading) {
      throw const KtvRecordingException('请先播放歌曲，确认伴唱音轨后再开始录音');
    }
    final backingSource = playback.currentSource;
    if (backingSource == null || backingSource == AudioSourceType.vocals) {
      throw const KtvRecordingException('KTV 录音只支持原唱伴唱或纯伴奏音轨');
    }
    final backingPath = audioAsset.getPathForSource(backingSource);
    if (backingPath == null || backingPath.trim().isEmpty) {
      throw const KtvRecordingException('当前伴唱音轨文件不可用');
    }

    if (!_microphoneService.currentState.isMonitoring) {
"""
new = """    final initialPlayback = _audioService.currentState;
    if (!initialPlayback.isPlaying ||
        initialPlayback.isBuffering ||
        initialPlayback.isLoading) {
      throw const KtvRecordingException('请先播放歌曲，确认伴唱音轨后再开始录音');
    }

    if (!_microphoneService.currentState.isMonitoring) {
"""
if old not in text:
    raise SystemExit("recording start preflight anchor not found")
text = text.replace(old, new, 1)
old = """    final directory = await _createSessionDirectory(project);
    final micStemPath = _join(directory.path, 'voice.wav');
    final manifestPath = _join(directory.path, 'session.json');
    final writer = Pcm16WavWriter();
    await writer.open(micStemPath);

    final now = DateTime.now();
"""
new = """    final directory = await _createSessionDirectory(project);
    final micStemPath = _join(directory.path, 'voice.wav');
    final manifestPath = _join(directory.path, 'session.json');
    final writer = Pcm16WavWriter();
    await writer.open(micStemPath);

    final playback = _audioService.currentState;
    if (!playback.isPlaying || playback.isBuffering || playback.isLoading) {
      await writer.close();
      throw const KtvRecordingException('麦克风准备期间歌曲停止了播放，请重新开始录音');
    }
    final backingSource = playback.currentSource;
    if (backingSource == null || backingSource == AudioSourceType.vocals) {
      await writer.close();
      throw const KtvRecordingException('KTV 录音只支持原唱伴唱或纯伴奏音轨');
    }
    final backingPath = audioAsset.getPathForSource(backingSource);
    if (backingPath == null || backingPath.trim().isEmpty) {
      await writer.close();
      throw const KtvRecordingException('当前伴唱音轨文件不可用');
    }

    final now = DateTime.now();
"""
if old not in text:
    raise SystemExit("recording late snapshot anchor not found")
text = text.replace(old, new, 1)
recording.write_text(text)

player = Path("lib/features/player/presentation/screens/player_screen.dart")
text = player.read_text()

old_imports = """import '../../domain/models/ktv_backing_mode.dart';
import '../../domain/models/ktv_microphone_state.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/services/audio_player_service.dart';
import '../../domain/services/ktv_microphone_service.dart';
"""
new_imports = """import '../../domain/models/ktv_backing_mode.dart';
import '../../domain/models/ktv_microphone_state.dart';
import '../../domain/models/ktv_recording_session.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/services/audio_player_service.dart';
import '../../domain/services/ktv_microphone_service.dart';
import '../../domain/services/ktv_recording_service.dart';
"""
if old_imports not in text:
    raise SystemExit("player recording imports anchor not found")
text = text.replace(old_imports, new_imports, 1)

old_state = """class _FullScreenKtvViewState extends State<_FullScreenKtvView> {
  late ProjectManifest _project;
  late final KtvMicrophoneService _microphoneService;
  StreamSubscription<PlaybackSessionState>? _sessionSubscription;
"""
new_state = """class _FullScreenKtvViewState extends State<_FullScreenKtvView> {
  late ProjectManifest _project;
  late final KtvMicrophoneService _microphoneService;
  late final KtvRecordingService _recordingService;
  StreamSubscription<PlaybackSessionState>? _sessionSubscription;
"""
if old_state not in text:
    raise SystemExit("fullscreen recording state anchor not found")
text = text.replace(old_state, new_state, 1)

text = text.replace(
    "    _microphoneService = ServiceLocatorGlobal.I.ktvMicrophoneService;\n    AppChromeController.enterImmersive();\n",
    "    _microphoneService = ServiceLocatorGlobal.I.ktvMicrophoneService;\n"
    "    _recordingService = ServiceLocatorGlobal.I.ktvRecordingService;\n"
    "    AppChromeController.enterImmersive();\n",
    1,
)

old_open_mic = """  Future<void> _openMicrophoneControls() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.bgElevated,
      builder: (context) => _KtvAudioControlsSheet(
        microphoneService: _microphoneService,
        audioService: widget.audioService,
      ),
    );
  }

  @override
  void dispose() {
    _sessionSubscription?.cancel();
    unawaited(_microphoneService.stopMonitoring());
    AppChromeController.exitImmersive();
"""
new_open_mic = """  Future<void> _openMicrophoneControls() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.bgElevated,
      builder: (context) => _KtvAudioControlsSheet(
        microphoneService: _microphoneService,
        audioService: widget.audioService,
        recordingLocked: _recordingService.currentState.isRecording,
      ),
    );
  }

  Future<void> _toggleRecording() async {
    try {
      if (_recordingService.currentState.isRecording) {
        final completed = await _recordingService.stopRecording();
        if (!mounted) return;
        setState(() {});
        if (completed != null) await _showTakeResult(completed);
        return;
      }
      await _recordingService.startRecording(_project);
      if (mounted) setState(() {});
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('KTV 录音失败：$error')),
      );
    }
  }

  Future<void> _showTakeResult(KtvRecordingSession session) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.bgElevated,
      builder: (context) => _KtvTakeResultSheet(
        initialSession: session,
        recordingService: _recordingService,
      ),
    );
  }

  Future<void> _shutdownKtvAudio() async {
    if (_recordingService.currentState.isRecording) {
      await _recordingService.stopRecording();
    }
    await _microphoneService.stopMonitoring();
  }

  @override
  void dispose() {
    _sessionSubscription?.cancel();
    unawaited(_shutdownKtvAudio());
    AppChromeController.exitImmersive();
"""
if old_open_mic not in text:
    raise SystemExit("fullscreen microphone methods anchor not found")
text = text.replace(old_open_mic, new_open_mic, 1)

# Capture a stable lock state for this frame. start/stop recording calls setState,
# while the recording button's own StreamBuilder handles duration updates.
text = text.replace(
    "    final ktvSources = availableKtvBackingModes(_project.audioAsset)\n        .map((mode) => mode.source)\n        .toList(growable: false);\n\n",
    "    final ktvSources = availableKtvBackingModes(_project.audioAsset)\n"
    "        .map((mode) => mode.source)\n"
    "        .toList(growable: false);\n"
    "    final recordingLocked = _recordingService.currentState.isRecording;\n\n",
    1,
)

# Lock source switching during a take.
old_sources = """                            if (ktvSources.length > 1) ...[
                              if (spec.isCompact || spec.isShort)
                                _CompactSourceMenu(
                                  availableSources: ktvSources,
                                  currentSource: playback.currentSource,
                                  onSourceChanged: widget.onSwitchSource,
                                  ktvLabels: true,
                                )
                              else
                                Flexible(
                                  child: _AudioSourceSelector(
                                    availableSources: ktvSources,
                                    currentSource: playback.currentSource,
                                    onSourceChanged: widget.onSwitchSource,
                                    compact: true,
                                    ktvLabels: true,
                                  ),
                                ),
                              const SizedBox(width: AppSpacing.sm),
                            ],
"""
new_sources = """                            if (ktvSources.length > 1) ...[
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
if old_sources not in text:
    raise SystemExit("fullscreen source selector anchor not found")
text = text.replace(old_sources, new_sources, 1)

# Insert record button before microphone settings.
record_button_anchor = """                            StreamBuilder<KtvMicrophoneState>(
                              stream: _microphoneService.stateStream,
"""
record_button = """                            StreamBuilder<KtvRecordingState>(
                              stream: _recordingService.stateStream,
                              initialData: _recordingService.currentState,
                              builder: (context, recordingSnapshot) {
                                final recording = recordingSnapshot.data ??
                                    _recordingService.currentState;
                                return Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (recording.isRecording && !spec.isShort)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: AppSpacing.xs,
                                        ),
                                        child: Text(
                                          _formatRecordingTime(
                                            recording.recordedDuration,
                                          ),
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium
                                              ?.copyWith(
                                                color: AppColors.error,
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                      ),
                                    SizedBox(
                                      width: spec.minimumInteractiveExtent,
                                      height: spec.minimumInteractiveExtent,
                                      child: IconButton.filled(
                                        tooltip: recording.isRecording
                                            ? '停止录音'
                                            : '开始 KTV 录音',
                                        onPressed: recording.isExporting
                                            ? null
                                            : _toggleRecording,
                                        style: IconButton.styleFrom(
                                          backgroundColor: recording.isRecording
                                              ? AppColors.error
                                              : AppColors.bgSurface,
                                          foregroundColor: AppColors.pureWhite,
                                        ),
                                        icon: Icon(
                                          recording.isRecording
                                              ? Icons.stop_rounded
                                              : Icons.fiber_manual_record_rounded,
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            StreamBuilder<KtvMicrophoneState>(
                              stream: _microphoneService.stateStream,
"""
if record_button_anchor not in text:
    raise SystemExit("record button anchor not found")
text = text.replace(record_button_anchor, record_button, 1)

# Lock seek and transport controls while the take is recording.
old_transport = """                            _ProgressBar(
                              state: playback,
                              onSeek: widget.onSeek,
                              compact: true,
                            ),
                            SizedBox(
                              height: spec.isShort ? 2 : AppSpacing.sm,
                            ),
                            _PlaybackControls(
                              isPlaying: playback.isPlaying,
                              isBuffering: playback.isBuffering,
                              canPrevious: session.currentItem != null,
                              canNext: session.canSkipNext,
                              onPrevious: widget.onSkipPrevious,
                              onPlayPause: widget.onPlayPause,
                              onNext: widget.onSkipNext,
                              compact: spec.isShort || spec.isCompact,
                            ),
"""
new_transport = """                            IgnorePointer(
                              ignoring: recordingLocked,
                              child: Opacity(
                                opacity: recordingLocked ? 0.55 : 1,
                                child: _ProgressBar(
                                  state: playback,
                                  onSeek: widget.onSeek,
                                  compact: true,
                                ),
                              ),
                            ),
                            SizedBox(
                              height: spec.isShort ? 2 : AppSpacing.sm,
                            ),
                            IgnorePointer(
                              ignoring: recordingLocked,
                              child: Opacity(
                                opacity: recordingLocked ? 0.55 : 1,
                                child: _PlaybackControls(
                                  isPlaying: playback.isPlaying,
                                  isBuffering: playback.isBuffering,
                                  canPrevious: session.currentItem != null,
                                  canNext: session.canSkipNext,
                                  onPrevious: widget.onSkipPrevious,
                                  onPlayPause: widget.onPlayPause,
                                  onNext: widget.onSkipNext,
                                  compact: spec.isShort || spec.isCompact,
                                ),
                              ),
                            ),
"""
if old_transport not in text:
    raise SystemExit("fullscreen transport anchor not found")
text = text.replace(old_transport, new_transport, 1)

# Prevent turning off the capture stream or changing backing loudness mid-take.
text = text.replace(
    "class _KtvAudioControlsSheet extends StatelessWidget {\n  final KtvMicrophoneService microphoneService;\n  final AudioPlayerService audioService;\n\n",
    "class _KtvAudioControlsSheet extends StatelessWidget {\n"
    "  final KtvMicrophoneService microphoneService;\n"
    "  final AudioPlayerService audioService;\n"
    "  final bool recordingLocked;\n\n",
    1,
)
text = text.replace(
    "    required this.microphoneService,\n    required this.audioService,\n  });\n",
    "    required this.microphoneService,\n"
    "    required this.audioService,\n"
    "    required this.recordingLocked,\n"
    "  });\n",
    1,
)
text = text.replace(
    "                        onChanged: microphone.isStarting\n                            ? null\n                            : (enabled) {\n",
    "                        onChanged: microphone.isStarting || recordingLocked\n                            ? null\n                            : (enabled) {\n",
    1,
)
# The first matching playback volume slider is inside the KTV sheet.
old_song_slider = """                      Slider(
                        value: playback.volume.clamp(0.0, 1.0).toDouble(),
                        min: 0,
                        max: 1,
                        divisions: 20,
                        onChanged: (value) =>
                            unawaited(audioService.setVolume(value)),
                      ),
"""
new_song_slider = """                      Slider(
                        value: playback.volume.clamp(0.0, 1.0).toDouble(),
                        min: 0,
                        max: 1,
                        divisions: 20,
                        onChanged: recordingLocked
                            ? null
                            : (value) =>
                                unawaited(audioService.setVolume(value)),
                      ),
"""
if old_song_slider not in text:
    raise SystemExit("KTV song volume slider anchor not found")
text = text.replace(old_song_slider, new_song_slider, 1)

# Result sheet keeps the raw take safe even if mix export fails or FFmpeg is not
# configured. It can update itself after a successful export.
result_sheet = r'''class _KtvTakeResultSheet extends StatefulWidget {
  final KtvRecordingSession initialSession;
  final KtvRecordingService recordingService;

  const _KtvTakeResultSheet({
    required this.initialSession,
    required this.recordingService,
  });

  @override
  State<_KtvTakeResultSheet> createState() => _KtvTakeResultSheetState();
}

class _KtvTakeResultSheetState extends State<_KtvTakeResultSheet> {
  late KtvRecordingSession _session;
  bool _exporting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _session = widget.initialSession;
  }

  Future<void> _exportMix() async {
    if (_exporting || !_session.alignmentReliable) return;
    setState(() {
      _exporting = true;
      _error = null;
    });
    try {
      final exported = await widget.recordingService.exportMix(_session);
      if (!mounted) return;
      setState(() {
        _session = exported;
        _exporting = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _exporting = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        spec.pageGutter,
        AppSpacing.sm,
        spec.pageGutter,
        AppSpacing.xxl,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    _session.alignmentReliable
                        ? Icons.check_circle_rounded
                        : Icons.warning_amber_rounded,
                    color: _session.alignmentReliable
                        ? AppColors.accent
                        : AppColors.warning,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'KTV 录音已保存',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '人声 stem（${_formatRecordingTime(_session.duration)}）',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: AppSpacing.xs),
              SelectableText(
                _session.micStemPath,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              if (!_session.alignmentReliable) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  _session.alignmentIssue ??
                      '播放时间轴在录音中发生变化，已保留人声 stem，但自动混音已禁用。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.warning,
                      ),
                ),
              ],
              if (_session.mixedOutputPath != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  '混音成品',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: AppSpacing.xs),
                SelectableText(
                  _session.mixedOutputPath!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                _PlaybackError(message: _error!),
              ],
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: !_session.alignmentReliable || _exporting
                    ? null
                    : _exportMix,
                icon: _exporting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.graphic_eq_rounded),
                label: Text(
                  _session.mixedOutputPath == null ? '导出 WAV 混音' : '重新导出混音',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

'''
anchor = "class _KtvAudioControlsSheet extends StatelessWidget {"
if anchor not in text:
    raise SystemExit("KTV audio sheet anchor not found")
text = text.replace(anchor, result_sheet + anchor, 1)

# Helper for compact recording clock / take duration labels.
format_anchor = "String _sourceLabel(AudioSourceType source) {"
format_helper = """String _formatRecordingTime(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) return '$hours:$minutes:$seconds';
  return '$minutes:$seconds';
}

"""
if format_anchor not in text:
    raise SystemExit("recording time helper anchor not found")
text = text.replace(format_anchor, format_helper + format_anchor, 1)

player.write_text(text)

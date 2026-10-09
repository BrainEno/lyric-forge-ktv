import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../../../project/domain/models/audio_asset.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../../../transcription/domain/services/transcription_settings_store.dart';
import '../../domain/models/ktv_recording_session.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/services/audio_player_service.dart';
import '../../domain/services/ktv_microphone_service.dart';
import '../../domain/services/ktv_recording_service.dart';
import 'pcm16_wav_writer.dart';

class LocalKtvRecordingService implements KtvRecordingService {
  final AudioPlayerService _audioService;
  final KtvMicrophoneService _microphoneService;
  final TranscriptionSettingsStore _settingsStore;
  final StreamController<KtvRecordingState> _stateController =
      StreamController<KtvRecordingState>.broadcast();

  KtvRecordingState _state = const KtvRecordingState();
  StreamSubscription<Uint8List>? _pcmSubscription;
  StreamSubscription<PlaybackState>? _playbackSubscription;
  Pcm16WavWriter? _writer;
  Stopwatch? _recordingClock;
  int _lastDurationEmitMs = 0;
  bool _alignmentReliable = true;
  String? _alignmentIssue;

  LocalKtvRecordingService({
    required AudioPlayerService audioService,
    required KtvMicrophoneService microphoneService,
    required TranscriptionSettingsStore settingsStore,
  })  : _audioService = audioService,
        _microphoneService = microphoneService,
        _settingsStore = settingsStore;

  @override
  Stream<KtvRecordingState> get stateStream => _stateController.stream;

  @override
  KtvRecordingState get currentState => _state;

  @override
  Future<void> startRecording(ProjectManifest project) async {
    if (_state.isRecording) {
      throw const KtvRecordingException('已经在录音中');
    }
    final audioAsset = project.audioAsset;
    if (audioAsset == null) {
      throw const KtvRecordingException('当前工程没有可录制的歌曲音频');
    }

    final initialPlayback = _audioService.currentState;
    if (!initialPlayback.isPlaying ||
        initialPlayback.isBuffering ||
        initialPlayback.isLoading) {
      throw const KtvRecordingException('请先播放歌曲，确认伴唱音轨后再开始录音');
    }

    if (!_microphoneService.currentState.isMonitoring) {
      await _microphoneService.startMonitoring();
      if (!_microphoneService.currentState.isMonitoring) {
        throw KtvRecordingException(
          _microphoneService.currentState.error ?? '无法启动麦克风，请检查系统权限和输入设备',
        );
      }
    }

    final directory = await _createSessionDirectory(project);
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
    final session = KtvRecordingSession(
      id: directory.uri.pathSegments
          .where((segment) => segment.isNotEmpty)
          .last,
      projectId: project.id,
      startedAt: now,
      backingSource: backingSource,
      backingPath: backingPath,
      startPosition: playback.position,
      duration: Duration.zero,
      micStemPath: micStemPath,
      manifestPath: manifestPath,
      backingVolume: playback.volume.clamp(0.0, 1.0).toDouble(),
      monitorMicGain: _microphoneService.currentState.micGain,
    );

    _writer = writer;
    _alignmentReliable = true;
    _alignmentIssue = null;
    _recordingClock = Stopwatch()..start();
    _lastDurationEmitMs = 0;

    _pcmSubscription = _microphoneService.rawPcm16Stream.listen(
      _handlePcmFrame,
      onError: (Object error, StackTrace stackTrace) {
        _markAlignmentIssue('麦克风输入在录音中断开：$error');
      },
    );
    _playbackSubscription = _audioService.stateStream.listen(_handlePlaybackState);

    _emit(
      _state.copyWith(
        isRecording: true,
        recordedDuration: Duration.zero,
        currentSession: session,
        clearError: true,
      ),
    );
    await _writeManifest(session);
  }

  void _handlePcmFrame(Uint8List bytes) {
    final writer = _writer;
    if (!_state.isRecording || writer == null) return;
    try {
      writer.addPcm16(bytes);
    } catch (error) {
      _markAlignmentIssue('写入人声录音失败：$error');
      return;
    }

    final duration = writer.duration;
    final durationMs = duration.inMilliseconds;
    if (durationMs - _lastDurationEmitMs >= 100) {
      _lastDurationEmitMs = durationMs;
      _emit(_state.copyWith(recordedDuration: duration));
    }
  }

  void _handlePlaybackState(PlaybackState playback) {
    final session = _state.currentSession;
    final clock = _recordingClock;
    if (!_state.isRecording || session == null || clock == null) return;

    if (playback.currentSource != session.backingSource) {
      _markAlignmentIssue('录音过程中切换了伴唱音轨');
      return;
    }
    if (!playback.isPlaying && clock.elapsed > const Duration(milliseconds: 350)) {
      _markAlignmentIssue('录音过程中歌曲被暂停或停止');
      return;
    }

    if (clock.elapsed < const Duration(seconds: 1)) return;
    final expected = session.startPosition + clock.elapsed;
    final drift = (playback.position - expected).abs();
    if (drift > const Duration(milliseconds: 900)) {
      _markAlignmentIssue('录音过程中播放位置发生跳变，无法保证混音对齐');
    }
  }

  void _markAlignmentIssue(String issue) {
    if (!_alignmentReliable) return;
    _alignmentReliable = false;
    _alignmentIssue = issue;
    final current = _state.currentSession;
    if (current != null) {
      _emit(
        _state.copyWith(
          currentSession: current.copyWith(
            alignmentReliable: false,
            alignmentIssue: issue,
          ),
          error: issue,
        ),
      );
    }
  }

  @override
  Future<KtvRecordingSession?> stopRecording() async {
    if (!_state.isRecording) return _state.lastCompletedSession;

    final current = _state.currentSession;
    final writer = _writer;
    _writer = null;
    _recordingClock?.stop();
    _recordingClock = null;

    final pcmSubscription = _pcmSubscription;
    _pcmSubscription = null;
    if (pcmSubscription != null) await pcmSubscription.cancel();
    final playbackSubscription = _playbackSubscription;
    _playbackSubscription = null;
    if (playbackSubscription != null) await playbackSubscription.cancel();

    if (current == null || writer == null) {
      _emit(
        _state.copyWith(
          isRecording: false,
          recordedDuration: Duration.zero,
          clearCurrentSession: true,
        ),
      );
      return null;
    }

    final duration = await writer.close();
    final completed = current.copyWith(
      completedAt: DateTime.now(),
      duration: duration,
      alignmentReliable: _alignmentReliable,
      alignmentIssue: _alignmentIssue,
    );
    await _writeManifest(completed);

    _emit(
      _state.copyWith(
        isRecording: false,
        recordedDuration: duration,
        clearCurrentSession: true,
        lastCompletedSession: completed,
        error: _alignmentIssue,
        clearError: _alignmentIssue == null,
      ),
    );
    return completed;
  }

  @override
  Future<KtvRecordingSession> exportMix(
    KtvRecordingSession session, {
    double voiceVolume = 1.0,
    double? backingVolume,
  }) async {
    if (_state.isRecording) {
      throw const KtvRecordingException('请先停止录音再导出混音');
    }
    if (!session.alignmentReliable) {
      throw KtvRecordingException(
        session.alignmentIssue ?? '本次录音的播放时间轴发生变化，无法安全生成自动混音',
      );
    }
    if (session.duration <= Duration.zero) {
      throw const KtvRecordingException('录音内容为空，无法导出');
    }
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
      throw const KtvRecordingException('当前版本的自动混音导出仅支持桌面端');
    }
    if (!await File(session.micStemPath).exists()) {
      throw const KtvRecordingException('人声录音文件不存在');
    }
    if (!await File(session.backingPath).exists()) {
      throw const KtvRecordingException('伴唱音轨文件不存在');
    }

    _emit(_state.copyWith(isExporting: true, clearError: true));
    try {
      final settings = await _settingsStore.load();
      final ffmpeg = settings?.ffmpegExecutable.trim().isNotEmpty == true
          ? settings!.ffmpegExecutable.trim()
          : 'ffmpeg';
      final outputPath = _join(File(session.manifestPath).parent.path, 'mix.wav');
      final args = buildKtvMixFfmpegArguments(
        session,
        outputPath: outputPath,
        voiceVolume: voiceVolume,
        backingVolume: backingVolume ?? session.backingVolume,
      );

      ProcessResult result;
      try {
        result = await Process.run(ffmpeg, args, runInShell: false);
      } on ProcessException catch (error) {
        throw KtvRecordingException(
          '无法启动 FFmpeg。人声录音已安全保存，可在配置本地 FFmpeg 后重新导出。\n$error',
        );
      }
      if (result.exitCode != 0 || !await File(outputPath).exists()) {
        final stderr = result.stderr.toString().trim();
        throw KtvRecordingException(
          'FFmpeg 混音失败${stderr.isEmpty ? '' : '：$stderr'}',
        );
      }

      final exported = session.copyWith(mixedOutputPath: outputPath);
      await _writeManifest(exported);
      _emit(
        _state.copyWith(
          isExporting: false,
          lastCompletedSession: exported,
          clearError: true,
        ),
      );
      return exported;
    } catch (error) {
      _emit(_state.copyWith(isExporting: false, error: error.toString()));
      rethrow;
    }
  }

  Future<Directory> _createSessionDirectory(ProjectManifest project) async {
    Directory projectDirectory;
    if (project.projectDirectory?.trim().isNotEmpty == true) {
      projectDirectory = Directory(project.projectDirectory!);
    } else {
      final support = await getApplicationSupportDirectory();
      projectDirectory = Directory(
        _join(_join(_join(support.path, 'LyricForge'), 'Projects'), project.id),
      );
    }

    final recordings = Directory(_join(projectDirectory.path, 'recordings'));
    await recordings.create(recursive: true);
    final stamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final directory = Directory(_join(recordings.path, 'take_$stamp'));
    await directory.create(recursive: true);
    return directory;
  }

  Future<void> _writeManifest(KtvRecordingSession session) async {
    final file = File(session.manifestPath);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(session.toJson()),
      flush: true,
    );
  }

  void _emit(KtvRecordingState next) {
    _state = next;
    if (!_stateController.isClosed) _stateController.add(next);
  }

  @override
  Future<void> dispose() async {
    await stopRecording();
    await _stateController.close();
  }
}

List<String> buildKtvMixFfmpegArguments(
  KtvRecordingSession session, {
  required String outputPath,
  double voiceVolume = 1.0,
  double? backingVolume,
}) {
  final voice = voiceVolume.clamp(0.0, 2.0).toDouble();
  final backing =
      (backingVolume ?? session.backingVolume).clamp(0.0, 1.0).toDouble();
  final startSeconds =
      (session.startPosition.inMicroseconds / Duration.microsecondsPerSecond)
          .toStringAsFixed(6);
  final durationSeconds =
      (session.duration.inMicroseconds / Duration.microsecondsPerSecond)
          .toStringAsFixed(6);
  final filter =
      '[0:a]atrim=start=$startSeconds:duration=$durationSeconds,'
      'asetpts=PTS-STARTPTS,volume=${backing.toStringAsFixed(4)}[b];'
      '[1:a]atrim=duration=$durationSeconds,asetpts=PTS-STARTPTS,'
      'volume=${voice.toStringAsFixed(4)}[v];'
      '[b][v]amix=inputs=2:duration=shortest:dropout_transition=0:'
      'normalize=0[m]';

  return <String>[
    '-hide_banner',
    '-loglevel',
    'error',
    '-y',
    '-i',
    session.backingPath,
    '-i',
    session.micStemPath,
    '-filter_complex',
    filter,
    '-map',
    '[m]',
    '-c:a',
    'pcm_s16le',
    outputPath,
  ];
}

String _join(String left, String right) =>
    left.endsWith(Platform.pathSeparator)
        ? '$left$right'
        : '$left${Platform.pathSeparator}$right';

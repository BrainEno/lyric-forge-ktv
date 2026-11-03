import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/data/services/file_audio_path_canonicalizer.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/audio_preview_state.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/ktv_microphone_state.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/ktv_recording_session.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_media_metadata.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_state.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/local_media_metadata_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_player_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_preview_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/ktv_microphone_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/ktv_recording_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/ktv_take_history_store.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/player/presentation/playback_screen_dependencies.dart';
import 'package:lyric_forge_ktv/features/player/presentation/screens/immersive_ktv_screen.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/ktv_recording_toolbar.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/ktv_take_history_sheet.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';
import 'package:lyric_forge_ktv/features/project/domain/repositories/project_repository.dart';

/// The fullscreen KTV screen lost every recording entry point when the
/// unreachable `_FullScreenKtvView` was deleted: the services existed, the UI
/// existed, nothing linked them. These tests assert the entry points on the
/// real screen (not by scanning its source) and that the mutation guard is
/// reachable from it.
void main() {
  final project = ProjectManifest(
    id: 'song',
    name: 'Song',
    createdAt: DateTime.utc(2026, 10, 10),
    updatedAt: DateTime.utc(2026, 10, 10),
    audioAsset: const AudioAsset(
      originalPath: '/music/backing.wav',
      format: 'wav',
    ),
    lyricDocument: const LyricDocument(
      language: 'zh',
      lines: [
        LyricLine(
          text: '一',
          startTime: Duration.zero,
          endTime: Duration(seconds: 2),
        ),
      ],
    ),
  );

  late _FakeRecordingService recording;
  late _FakeMicrophoneService microphone;

  setUp(() {
    recording = _FakeRecordingService();
    microphone = _FakeMicrophoneService();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ImmersiveKtvScreen(
          initialProjectId: project.id,
          dependencies: ImmersiveKtvDependencies(
            projectRepository: _FakeProjectRepository(project),
            metadataRepository: _FakeMetadataRepository(),
            audioPlayer: _FakeAudioPlayerService(),
            playbackSession: _FakePlaybackSession(),
            pathCanonicalizer: const FileAudioPathCanonicalizer(),
            microphoneService: microphone,
            recordingService: recording,
            takeHistoryStore: _FakeTakeHistoryStore(),
            previewService: _FakePreviewService(),
          ),
        ),
      ),
    );
    // One frame for the project load.
    await tester.pump();
  }

  Future<void> disposeScreen(WidgetTester tester) async {
    // Disposes the surface's idle-hide timer along with the screen.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  testWidgets('全屏 KTV 上有录音、演唱历史和麦克风入口', (tester) async {
    await pumpScreen(tester);

    for (final key in [
      KtvRecordingToolbar.recordButtonKey,
      KtvRecordingToolbar.historyButtonKey,
      KtvRecordingToolbar.microphoneButtonKey,
    ]) {
      final button = tester.widget<IconButton>(find.byKey(key));
      expect(button.onPressed, isNotNull, reason: '$key 应当可点击');
    }

    await disposeScreen(tester);
  });

  testWidgets('点击录音按钮用当前工程开始录制', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byKey(KtvRecordingToolbar.recordButtonKey));
    await tester.pump();

    expect(recording.log, ['start:song']);

    await disposeScreen(tester);
  });

  testWidgets('导出进行中时录音按钮停用，历史入口给出导出提示', (tester) async {
    recording.emit(const KtvRecordingState(isExporting: true));
    await pumpScreen(tester);

    final record = tester.widget<IconButton>(
      find.byKey(KtvRecordingToolbar.recordButtonKey),
    );
    expect(record.onPressed, isNull);
    final history = tester.widget<IconButton>(
      find.byKey(KtvRecordingToolbar.historyButtonKey),
    );
    expect(history.onPressed, isNull);

    // Nothing opened behind the disabled button.
    expect(find.byType(KtvTakeHistorySheet), findsNothing);

    await disposeScreen(tester);
  });

  testWidgets('退出全屏 KTV 会停止仍在进行的录音', (tester) async {
    recording.emit(const KtvRecordingState(isRecording: true));
    await pumpScreen(tester);

    await disposeScreen(tester);
    await tester.pump();

    expect(recording.log, contains('stop'));
  });
}

class _FakeRecordingService implements KtvRecordingService {
  final StreamController<KtvRecordingState> _states =
      StreamController<KtvRecordingState>.broadcast();
  final List<String> log = <String>[];
  KtvRecordingState _state = const KtvRecordingState();

  void emit(KtvRecordingState state) {
    _state = state;
    _states.add(state);
  }

  @override
  KtvRecordingState get currentState => _state;

  @override
  Stream<KtvRecordingState> get stateStream => _states.stream;

  @override
  Future<void> startRecording(ProjectManifest project) async {
    log.add('start:${project.id}');
    emit(const KtvRecordingState(isRecording: true));
  }

  @override
  Future<KtvRecordingSession?> stopRecording() async {
    log.add('stop');
    emit(const KtvRecordingState());
    return null;
  }

  @override
  Future<KtvRecordingSession> exportMix(
    KtvRecordingSession session, {
    double voiceVolume = 1.0,
    double? backingVolume,
  }) async => session;

  @override
  Future<void> dispose() async {
    await _states.close();
  }
}

class _FakeMicrophoneService implements KtvMicrophoneService {
  final StreamController<KtvMicrophoneState> _states =
      StreamController<KtvMicrophoneState>.broadcast();
  final StreamController<Uint8List> _pcm =
      StreamController<Uint8List>.broadcast();

  @override
  KtvMicrophoneState get currentState => const KtvMicrophoneState();

  @override
  Stream<KtvMicrophoneState> get stateStream => _states.stream;

  @override
  Stream<Uint8List> get rawPcm16Stream => _pcm.stream;

  @override
  Future<void> refreshInputDevices() async {}

  @override
  Future<void> selectInputDevice(String? deviceId) async {}

  @override
  Future<void> startMonitoring() async {}

  @override
  Future<void> stopMonitoring() async {}

  @override
  Future<void> setMicGain(double gain) async {}

  @override
  Future<void> setMonitorDelay(Duration delay) async {}

  @override
  Future<void> dispose() async {
    await _states.close();
    await _pcm.close();
  }
}

class _FakeAudioPlayerService implements AudioPlayerService {
  final StreamController<PlaybackState> _states =
      StreamController<PlaybackState>.broadcast();

  @override
  PlaybackState get currentState => const PlaybackState.idle();

  @override
  Stream<PlaybackState> get stateStream => _states.stream;

  @override
  Stream<Duration> get positionStream => const Stream.empty();

  @override
  Stream<Duration?> get durationStream => const Stream.empty();

  @override
  Future<void> dispose() async {
    await _states.close();
  }

  @override
  Future<void> loadAudioUri({
    required Uri uri,
    AudioSourceType source = AudioSourceType.original,
  }) async {}

  @override
  Future<void> loadProjectAudio({
    required AudioAsset audioAsset,
    AudioSourceType preferredSource = AudioSourceType.instrumental,
  }) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> switchSource(AudioSourceType source) async {}
}

class _FakePlaybackSession implements PlaybackSessionService {
  final StreamController<PlaybackSessionState> _states =
      StreamController<PlaybackSessionState>.broadcast();

  @override
  PlaybackSessionState get currentState => const PlaybackSessionState();

  @override
  Stream<PlaybackSessionState> get stateStream => _states.stream;

  @override
  PlaybackState get playbackState => const PlaybackState.idle();

  @override
  bool get canSkipPrevious => false;

  @override
  bool get canSkipNext => false;

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> togglePlayPause() async {}

  @override
  Future<void> skipPrevious() async {}

  @override
  Future<void> skipNext() async {}

  @override
  Future<void> dispose() async {
    await _states.close();
  }
}

class _FakeProjectRepository implements ProjectRepository {
  _FakeProjectRepository(this.project);

  final ProjectManifest project;

  @override
  Future<ProjectManifest?> getProjectById(String id) async =>
      id == project.id ? project : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMetadataRepository implements LocalMediaMetadataRepository {
  @override
  Future<LocalMediaMetadata?> getForAudio(String sourcePath) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTakeHistoryStore implements KtvTakeHistoryStore {
  @override
  Future<KtvTakeHistoryScanResult> scanProject(ProjectManifest project) async =>
      const KtvTakeHistoryScanResult(takes: [], recoveredCount: 0);

  @override
  Future<List<KtvRecordingSession>> listProject(
    ProjectManifest project,
  ) async => const [];

  @override
  Future<KtvRecordingSession> updateProjectTakeMetadata(
    ProjectManifest project,
    KtvRecordingSession take, {
    String? displayName,
    bool clearDisplayName = false,
    bool? isFavorite,
  }) async => take;

  @override
  Future<void> deleteProjectTake(
    ProjectManifest project,
    KtvRecordingSession take,
  ) async {}
}

class _FakePreviewService implements AudioPreviewService {
  final StreamController<AudioPreviewState> _states =
      StreamController<AudioPreviewState>.broadcast();

  @override
  AudioPreviewState get currentState => const AudioPreviewState.idle();

  @override
  Stream<AudioPreviewState> get stateStream => _states.stream;

  @override
  Future<Duration?> loadFile(String path) async => const Duration(seconds: 30);

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    await _states.close();
  }
}

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/data/services/local_ktv_recording_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/ktv_microphone_state.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/ktv_recording_session.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_state.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_player_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/ktv_microphone_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_settings_store.dart';

void main() {
  test('recording writes through the injected project storage resolver', () async {
    final root = await Directory.systemTemp.createTemp('ktv-recording-storage-');
    final managed = Directory(_join(root.path, 'managed-project'));
    final audio = _FakeAudioPlayerService(_playing(AudioSourceType.original));
    final microphone = _FakeMicrophoneService(
      initialState: const KtvMicrophoneState(isMonitoring: true),
    );
    var resolverCalls = 0;
    final service = LocalKtvRecordingService(
      audioService: audio,
      microphoneService: microphone,
      settingsStore: _FakeSettingsStore(),
      projectDirectoryResolver: (project) async {
        resolverCalls++;
        expect(project.id, 'song');
        return managed;
      },
    );

    addTearDown(() async {
      await service.dispose();
      await microphone.dispose();
      await audio.dispose();
      if (await root.exists()) await root.delete(recursive: true);
    });

    await service.startRecording(_project());

    final session = service.currentState.currentSession;
    expect(service.currentState.isRecording, isTrue);
    expect(session, isNotNull);
    expect(resolverCalls, 1);
    expect(
      File(session!.manifestPath).parent.parent.path,
      _join(managed.path, 'recordings'),
    );
    expect(await File(session.manifestPath).exists(), isTrue);
    expect(await File(session.micStemPath).exists(), isTrue);

    await service.stopRecording();
    expect(service.currentState.isRecording, isFalse);
  });

  test('failed final playback validation creates no orphan take', () async {
    final root = await Directory.systemTemp.createTemp('ktv-recording-orphan-');
    final managed = Directory(_join(root.path, 'managed-project'));
    final audio = _FakeAudioPlayerService(_playing(AudioSourceType.original));
    late _FakeMicrophoneService microphone;
    microphone = _FakeMicrophoneService(
      initialState: const KtvMicrophoneState(),
      onStartMonitoring: () {
        audio.setState(_playing(AudioSourceType.vocals));
      },
    );
    var resolverCalls = 0;
    final service = LocalKtvRecordingService(
      audioService: audio,
      microphoneService: microphone,
      settingsStore: _FakeSettingsStore(),
      projectDirectoryResolver: (project) async {
        resolverCalls++;
        return managed;
      },
    );

    addTearDown(() async {
      await service.dispose();
      await microphone.dispose();
      await audio.dispose();
      if (await root.exists()) await root.delete(recursive: true);
    });

    await expectLater(
      service.startRecording(_project()),
      throwsA(
        isA<KtvRecordingException>().having(
          (error) => error.message,
          'message',
          contains('只支持原唱伴唱或纯伴奏音轨'),
        ),
      ),
    );

    expect(service.currentState.isRecording, isFalse);
    expect(resolverCalls, 0);
    expect(await managed.exists(), isFalse);
  });
}

ProjectManifest _project() => ProjectManifest(
      id: 'song',
      name: 'Song',
      createdAt: DateTime.utc(2026, 10, 9),
      updatedAt: DateTime.utc(2026, 10, 9),
      audioAsset: const AudioAsset(
        originalPath: '/music/song.wav',
        vocalPath: '/music/vocals.wav',
        instrumentalPath: '/music/instrumental.wav',
        format: 'wav',
      ),
    );

PlaybackState _playing(AudioSourceType source) => PlaybackState(
      isPlaying: true,
      isBuffering: false,
      isCompleted: false,
      isLoading: false,
      position: const Duration(seconds: 12),
      duration: const Duration(minutes: 3),
      bufferedPosition: const Duration(minutes: 3),
      speed: 1,
      volume: 0.8,
      currentSource: source,
    );

String _join(String left, String right) =>
    left.endsWith(Platform.pathSeparator)
        ? '$left$right'
        : '$left${Platform.pathSeparator}$right';

class _FakeAudioPlayerService implements AudioPlayerService {
  PlaybackState _state;
  final StreamController<PlaybackState> _stateController =
      StreamController<PlaybackState>.broadcast();

  _FakeAudioPlayerService(this._state);

  void setState(PlaybackState next) {
    _state = next;
    _stateController.add(next);
  }

  @override
  PlaybackState get currentState => _state;

  @override
  Stream<PlaybackState> get stateStream => _stateController.stream;

  @override
  Stream<Duration> get positionStream => const Stream<Duration>.empty();

  @override
  Stream<Duration?> get durationStream => const Stream<Duration?>.empty();

  @override
  Future<void> loadProjectAudio({
    required AudioAsset audioAsset,
    AudioSourceType preferredSource = AudioSourceType.instrumental,
  }) async {}

  @override
  Future<void> loadAudioUri({
    required Uri uri,
    AudioSourceType source = AudioSourceType.original,
  }) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> switchSource(AudioSourceType source) async {}

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> dispose() => _stateController.close();
}

class _FakeMicrophoneService implements KtvMicrophoneService {
  KtvMicrophoneState _state;
  final void Function()? onStartMonitoring;
  final StreamController<KtvMicrophoneState> _stateController =
      StreamController<KtvMicrophoneState>.broadcast();
  final StreamController<Uint8List> _pcmController =
      StreamController<Uint8List>.broadcast();

  _FakeMicrophoneService({
    required KtvMicrophoneState initialState,
    this.onStartMonitoring,
  }) : _state = initialState;

  @override
  KtvMicrophoneState get currentState => _state;

  @override
  Stream<KtvMicrophoneState> get stateStream => _stateController.stream;

  @override
  Stream<Uint8List> get rawPcm16Stream => _pcmController.stream;

  @override
  Future<void> startMonitoring() async {
    onStartMonitoring?.call();
    _state = _state.copyWith(isMonitoring: true, clearError: true);
    _stateController.add(_state);
  }

  @override
  Future<void> stopMonitoring() async {
    _state = _state.copyWith(isMonitoring: false);
    _stateController.add(_state);
  }

  @override
  Future<void> refreshInputDevices() async {}

  @override
  Future<void> selectInputDevice(String? deviceId) async {}

  @override
  Future<void> setMicGain(double gain) async {
    _state = _state.copyWith(micGain: gain);
    _stateController.add(_state);
  }

  @override
  Future<void> setMonitorDelay(Duration delay) async {
    _state = _state.copyWith(monitorDelay: delay);
    _stateController.add(_state);
  }

  @override
  Future<void> dispose() async {
    await _stateController.close();
    await _pcmController.close();
  }
}

class _FakeSettingsStore implements TranscriptionSettingsStore {
  @override
  Future<TranscriptionConfig?> load() async => null;

  @override
  Future<void> save(TranscriptionConfig config) async {}

  @override
  Future<void> clear() async {}
}

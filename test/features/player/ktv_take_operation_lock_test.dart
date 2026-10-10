import 'dart:async';
import 'dart:convert';
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
  test('active export blocks another export and a new recording', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final gate = Completer<ProcessResult>();
    List<String>? ffmpegArgs;
    final service = fixture.service(
      processRunner: (executable, arguments) {
        ffmpegArgs = arguments;
        return gate.future;
      },
    );
    addTearDown(service.dispose);

    final first = service.exportMix(fixture.session);
    await _waitUntil(() => service.currentState.isExporting);

    await expectLater(
      service.exportMix(fixture.session),
      throwsA(
        isA<KtvRecordingException>().having(
          (error) => error.message,
          'message',
          contains('已有混音正在导出'),
        ),
      ),
    );
    await expectLater(
      service.startRecording(fixture.project),
      throwsA(
        isA<KtvRecordingException>().having(
          (error) => error.message,
          'message',
          contains('混音正在导出'),
        ),
      ),
    );

    final changed = fixture.session.copyWith(
      displayName: '高音最好的一次',
      isFavorite: true,
    );
    await fixture.manifest.writeAsString(jsonEncode(changed.toJson()), flush: true);
    await File(ffmpegArgs!.last).writeAsBytes([1, 2, 3], flush: true);
    gate.complete(ProcessResult(123, 0, '', ''));

    final exported = await first;
    expect(service.currentState.isExporting, isFalse);
    expect(exported.displayName, '高音最好的一次');
    expect(exported.isFavorite, isTrue);
    expect(exported.mixedOutputPath, ffmpegArgs!.last);

    final persisted = KtvRecordingSession.fromJson(
      jsonDecode(await fixture.manifest.readAsString()) as Map<String, dynamic>,
    );
    expect(persisted.displayName, '高音最好的一次');
    expect(persisted.isFavorite, isTrue);
    expect(persisted.mixedOutputPath, ffmpegArgs!.last);
  });

  test('failed export always releases the operation lock', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final service = fixture.service(
      processRunner: (executable, arguments) async =>
          ProcessResult(123, 1, '', 'fake ffmpeg failure'),
    );
    addTearDown(service.dispose);

    await expectLater(
      service.exportMix(fixture.session),
      throwsA(isA<KtvRecordingException>()),
    );

    expect(service.currentState.isExporting, isFalse);
  });

  test('player history mutations have dynamic export/recording guards', () async {
    final source = await File(
      'lib/features/player/presentation/screens/player_screen.dart',
    ).readAsString();
    expect(source, contains('bool _takeMutationLocked()'));
    expect(source, contains('state.isRecording || state.isExporting'));
    expect(source, contains('_showTakeMutationLockedMessage()'));
    expect(source, contains('混音正在导出，完成前不能删除、重命名或收藏录音'));
    expect(
      RegExp(r'if \(_takeMutationLocked\(\)\)').allMatches(source).length,
      greaterThanOrEqualTo(5),
    );
  });
}

class _Fixture {
  final Directory root;
  final File manifest;
  final KtvRecordingSession session;
  final ProjectManifest project;
  final _FakeAudioPlayerService audio;
  final _FakeMicrophoneService microphone;

  _Fixture({
    required this.root,
    required this.manifest,
    required this.session,
    required this.project,
    required this.audio,
    required this.microphone,
  });

  static Future<_Fixture> create() async {
    final root = await Directory.systemTemp.createTemp('ktv-export-lock-');
    final take = Directory('${root.path}${Platform.pathSeparator}take_test');
    await take.create(recursive: true);
    final voice = File('${take.path}${Platform.pathSeparator}voice.wav');
    final backing = File('${root.path}${Platform.pathSeparator}backing.wav');
    final manifest = File('${take.path}${Platform.pathSeparator}session.json');
    await voice.writeAsBytes([1, 2, 3]);
    await backing.writeAsBytes([4, 5, 6]);
    final session = KtvRecordingSession(
      id: 'take_test',
      projectId: 'song',
      startedAt: DateTime.utc(2026, 10, 10),
      completedAt: DateTime.utc(2026, 10, 10, 0, 1),
      backingSource: AudioSourceType.instrumental,
      backingPath: backing.path,
      startPosition: Duration.zero,
      duration: const Duration(seconds: 30),
      micStemPath: voice.path,
      manifestPath: manifest.path,
      backingVolume: 0.8,
      monitorMicGain: 1,
    );
    await manifest.writeAsString(jsonEncode(session.toJson()), flush: true);
    final project = ProjectManifest(
      id: 'song',
      name: 'Song',
      createdAt: DateTime.utc(2026, 10, 10),
      updatedAt: DateTime.utc(2026, 10, 10),
      audioAsset: AudioAsset(
        originalPath: backing.path,
        instrumentalPath: backing.path,
        format: 'wav',
      ),
    );
    return _Fixture(
      root: root,
      manifest: manifest,
      session: session,
      project: project,
      audio: _FakeAudioPlayerService(),
      microphone: _FakeMicrophoneService(),
    );
  }

  LocalKtvRecordingService service({
    required Future<ProcessResult> Function(String, List<String>) processRunner,
  }) {
    return LocalKtvRecordingService(
      audioService: audio,
      microphoneService: microphone,
      settingsStore: _FakeSettingsStore(),
      projectDirectoryResolver: (_) async => root,
      processRunner: processRunner,
    );
  }

  Future<void> dispose() async {
    await microphone.dispose();
    await audio.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  }
}

Future<void> _waitUntil(bool Function() predicate) async {
  for (var index = 0; index < 100; index++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('condition was not reached');
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
  Future<void> dispose() => _states.close();

  @override
  Future<void> loadAudioUri({required Uri uri, AudioSourceType source = AudioSourceType.original}) async {}

  @override
  Future<void> loadProjectAudio({required AudioAsset audioAsset, AudioSourceType preferredSource = AudioSourceType.instrumental}) async {}

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

class _FakeMicrophoneService implements KtvMicrophoneService {
  final StreamController<KtvMicrophoneState> _states =
      StreamController<KtvMicrophoneState>.broadcast();
  final StreamController<Uint8List> _pcm = StreamController<Uint8List>.broadcast();

  @override
  KtvMicrophoneState get currentState => const KtvMicrophoneState();
  @override
  Stream<Uint8List> get rawPcm16Stream => _pcm.stream;
  @override
  Stream<KtvMicrophoneState> get stateStream => _states.stream;
  @override
  Future<void> dispose() async {
    await _states.close();
    await _pcm.close();
  }
  @override
  Future<void> refreshInputDevices() async {}
  @override
  Future<void> selectInputDevice(String? deviceId) async {}
  @override
  Future<void> setMicGain(double gain) async {}
  @override
  Future<void> setMonitorDelay(Duration delay) async {}
  @override
  Future<void> startMonitoring() async {}
  @override
  Future<void> stopMonitoring() async {}
}

class _FakeSettingsStore implements TranscriptionSettingsStore {
  @override
  Future<void> clear() async {}
  @override
  Future<TranscriptionConfig?> load() async => null;
  @override
  Future<void> save(TranscriptionConfig config) async {}
}

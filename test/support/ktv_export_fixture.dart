import 'dart:convert';
import 'dart:io';

import 'package:lyric_forge_ktv/features/player/domain/models/ktv_recording_session.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_player_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/ktv_microphone_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_settings_store.dart';

/// A real on-disk take with no audio device or FFmpeg process.
class KtvExportFixture {
  final Directory root;
  final File backing;
  final File voice;
  final File manifest;
  final KtvRecordingSession session;

  KtvExportFixture._(
    this.root,
    this.backing,
    this.voice,
    this.manifest,
    this.session,
  );

  static Future<KtvExportFixture> create() async {
    final root = await Directory.systemTemp.createTemp('ktv assembly 中文 ');
    final take = Directory('${root.path}${Platform.pathSeparator}take 1');
    await take.create(recursive: true);
    final backing = File('${root.path}${Platform.pathSeparator}伴奏 audio.wav');
    final voice = File('${take.path}${Platform.pathSeparator}人声 voice.wav');
    final manifest = File('${take.path}${Platform.pathSeparator}session.json');
    await backing.writeAsBytes([1, 2, 3]);
    await voice.writeAsBytes([4, 5, 6]);
    final session = KtvRecordingSession(
      id: 'take-1',
      projectId: 'project-1',
      startedAt: DateTime.utc(2026, 1, 1),
      completedAt: DateTime.utc(2026, 1, 1, 0, 1),
      backingSource: AudioSourceType.instrumental,
      backingPath: backing.path,
      startPosition: const Duration(milliseconds: 1350),
      duration: const Duration(milliseconds: 3450),
      micStemPath: voice.path,
      manifestPath: manifest.path,
      backingVolume: 0.7,
      monitorMicGain: 1,
      displayName: '原始名称',
    );
    final fixture = KtvExportFixture._(root, backing, voice, manifest, session);
    await fixture.writeSession(session);
    return fixture;
  }

  Future<void> writeSession(KtvRecordingSession session) async {
    await manifest.writeAsString(jsonEncode(session.toJson()), flush: true);
  }

  Future<KtvRecordingSession> readSession() async =>
      KtvRecordingSession.fromJson(
        jsonDecode(await manifest.readAsString()) as Map<String, dynamic>,
      );

  Future<void> dispose() async {
    if (await root.exists()) await root.delete(recursive: true);
  }
}

class MutableSettingsStore implements TranscriptionSettingsStore {
  TranscriptionConfig? value;
  Object? failure;
  int loads = 0;

  @override
  Future<TranscriptionConfig?> load() async {
    loads++;
    if (failure != null) throw failure!;
    return value;
  }

  @override
  Future<void> save(TranscriptionConfig config) async {
    value = config;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

TranscriptionConfig configWithFfmpeg(String path) => TranscriptionConfig(
  whisperExecutable: '',
  modelPath: '',
  ffmpegExecutable: path,
);

class UnusedAudioPlayer implements AudioPlayerService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class UnusedMicrophone implements KtvMicrophoneService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class CapturingProcessRunner {
  final executables = <String>[];
  final argumentLists = <List<String>>[];
  int exitCode = 0;
  String stderr = '';
  bool createOutput = true;
  Object? failure;

  Future<ProcessResult> run(String executable, List<String> arguments) async {
    executables.add(executable);
    argumentLists.add(List.of(arguments));
    if (failure != null) throw failure!;
    if (createOutput && exitCode == 0) {
      await File(arguments.last).writeAsBytes([9, 8, 7], flush: true);
    }
    return ProcessResult(42, exitCode, '', stderr);
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/local_project_vocal_separator.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/separator_manifest.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/vocal_separator_runtime.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/vocal_separation_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/project_vocal_separator.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/vocal_separation_planner.dart';

const _revision = 'htdemucs-ft-vocals-onnx-v1';
const _config = TranscriptionConfig(
  whisperExecutable: 'whisper',
  modelPath: 'model',
  ffmpegExecutable: 'ffmpeg',
  downloadProxy: 'http://proxy.local:7890',
);

const _manifest = SeparatorManifest(
  separatorRevision: _revision,
  platform: 'windows-x64',
  executable: 'bin/lyricforge-separator.exe',
  modelFile: 'models/htdemucs_ft_vocals.onnx',
  modelBytes: 1,
  modelSha256:
      'aa11bb22cc33dd44ee55ff6600778899aa11bb22cc33dd44ee55ff6600778899',
  vocalsIndex: 3,
  providers: ['dml', 'cpu'],
);

class _Runtime implements VocalSeparatorRuntime {
  Object? error;
  bool supported = true;
  int cancels = 0;
  int installs = 0;
  String? lastProxy;

  @override
  String get separatorRevision => _revision;

  @override
  bool get supportsCurrentPlatform => supported;

  @override
  Future<VocalSeparatorInstallation?> inspect() async => null;

  @override
  Future<VocalSeparatorInstallation> ensureInstalled({
    String proxy = '',
    void Function(double fraction, String message)? onProgress,
  }) async {
    installs++;
    lastProxy = proxy;
    onProgress?.call(0.5, '正在下载人声分离组件 50%');
    final error = this.error;
    if (error != null) throw error;
    return const VocalSeparatorInstallation(
      root: '/opt/separator',
      manifest: _manifest,
    );
  }

  @override
  void cancel() => cancels++;
}

class _FakeProcess implements Process {
  final _stdout = StreamController<List<int>>();
  final _stderr = StreamController<List<int>>();
  final _exit = Completer<int>();
  bool killed = false;

  void emit(String line) => _stdout.add(utf8.encode('$line\r\n'));
  void error(String line) => _stderr.add(utf8.encode('$line\n'));

  void finish(int code) {
    if (_exit.isCompleted) return;
    unawaited(_stdout.close());
    unawaited(_stderr.close());
    _exit.complete(code);
  }

  @override
  Stream<List<int>> get stdout => _stdout.stream;
  @override
  Stream<List<int>> get stderr => _stderr.stream;
  @override
  Future<int> get exitCode => _exit.future;
  @override
  int get pid => 4242;
  @override
  IOSink get stdin => throw UnsupportedError('stdin is not used');
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    finish(-1);
    return true;
  }
}

typedef _Behaviour =
    Future<void> Function(List<String> arguments, _FakeProcess process);

class _Processes {
  final calls = <List<String>>[];
  final executables = <String>[];
  _Behaviour ffmpeg = _convert;
  _Behaviour separator = _separate;
  Object? startError;
  _FakeProcess? last;

  Future<Process> start(String executable, List<String> arguments) async {
    executables.add(executable);
    calls.add(arguments);
    final error = startError;
    if (error != null) throw error;
    final process = _FakeProcess();
    last = process;
    final behaviour = arguments.contains('--model') ? separator : ffmpeg;
    scheduleMicrotask(() => unawaited(behaviour(arguments, process)));
    return process;
  }
}

String _argument(List<String> arguments, String flag) =>
    arguments[arguments.indexOf(flag) + 1];

Future<void> _convert(List<String> arguments, _FakeProcess process) async {
  await File(arguments.last).writeAsBytes(List<int>.filled(1000, 1));
  process.finish(0);
}

Future<void> _separate(List<String> arguments, _FakeProcess process) async {
  await _writeStems(arguments);
  for (final line in [
    'LF_STAGE load-model',
    'LF_PROVIDER dml',
    'LF_STAGE separate',
    'LF_PROGRESS 0.5000',
    'LF_PROGRESS 1.0000',
    'LF_STAGE write',
    'LF_STATS mix_rms=0.2 vocals_rms=0.08 accompaniment_rms=0.15 seconds=3',
    'LF_DONE vocals=x accompaniment=y',
  ]) {
    process.emit(line);
  }
  process.finish(0);
}

Future<void> _writeStems(List<String> arguments) async {
  final output = _argument(arguments, '--output-dir');
  await File('$output/vocals.wav').writeAsBytes(List<int>.filled(500, 2));
  await File(
    '$output/accompaniment.wav',
  ).writeAsBytes(List<int>.filled(500, 3));
}

class _Fixture {
  _Fixture(this.root, this.project);

  final Directory root;
  final ProjectManifest project;
  final runtime = _Runtime();
  final processes = _Processes();
  final progress = <TranscriptionProgress>[];

  String get workDirectory => '${root.path}/stems';

  LocalProjectVocalSeparator separator() => LocalProjectVocalSeparator(
    runtime: runtime,
    startProcess: processes.start,
    now: () => DateTime.utc(2026, 11, 18, 12),
  );

  Future<ProjectVocalSeparation> run({
    LocalProjectVocalSeparator? using,
    ProjectManifest? project,
    TranscriptionConfig config = _config,
  }) => (using ?? separator()).separate(
    project ?? this.project,
    config: config,
    workDirectory: workDirectory,
    onProgress: progress.add,
  );

  List<String> runDirectories() {
    final directory = Directory(workDirectory);
    if (!directory.existsSync()) return const [];
    return directory
        .listSync()
        .whereType<Directory>()
        .map((entity) => entity.path.split(Platform.pathSeparator).last)
        .toList();
  }
}

Future<_Fixture> _fixture({
  String? vocalPath,
  Map<String, dynamic>? metadata,
}) async {
  final root = await Directory.systemTemp.createTemp('vocal-separation-');
  addTearDown(() => root.delete(recursive: true));
  final song = File('${root.path}/歌曲.flac');
  await song.writeAsBytes(List<int>.filled(2000, 7));
  final now = DateTime.utc(2026, 11, 18);
  return _Fixture(
    root,
    ProjectManifest(
      id: 'p',
      name: 'Song',
      createdAt: now,
      updatedAt: now,
      audioAsset: AudioAsset(
        originalPath: song.path,
        format: 'flac',
        vocalPath: vocalPath,
        metadata: metadata ?? const {'title': 'Song'},
      ),
      projectDirectory: root.path,
    ),
  );
}

Matcher get _cancelled => throwsA(
  isA<TranscriptionException>().having(
    (error) => error.kind,
    'kind',
    TranscriptionFailureKind.cancelled,
  ),
);

void main() {
  test('separates, links the stem and records where it came from', () async {
    final fixture = await _fixture();
    final result = await fixture.run();

    final outcome = result.outcome;
    expect(outcome.status, VocalSeparationStatus.separated);
    expect(outcome.provider, 'dml');
    expect(outcome.stats?.vocalsRms, 0.08);
    expect(outcome.vocalPath, endsWith('vocals.wav'));
    expect(outcome.accompanimentPath, endsWith('accompaniment.wav'));
    expect(File(outcome.vocalPath!).existsSync(), isTrue);

    final audio = result.updatedAudio!;
    expect(audio.vocalPath, outcome.vocalPath);
    expect(audio.metadata['title'], 'Song', reason: 'metadata is kept');
    final marker = VocalStemMarker.fromAudioMetadata(audio.metadata)!;
    expect(marker.separatorRevision, _revision);
    expect(marker.vocalPath, outcome.vocalPath);
    expect(marker.provider, 'dml');
    expect(marker.sourceFingerprint, contains('歌曲.flac'));

    // The proxy reaches the installer; ffmpeg decodes to 44.1 kHz stereo.
    expect(fixture.runtime.lastProxy, 'http://proxy.local:7890');
    final ffmpeg = fixture.processes.calls.first;
    expect(fixture.processes.executables.first, 'ffmpeg');
    expect(ffmpeg, containsAllInOrder(['-ac', '2', '-ar', '44100']));
    expect(ffmpeg, contains(fixture.project.audioAsset!.originalPath));
    final separator = fixture.processes.calls.last;
    expect(
      fixture.processes.executables.last,
      endsWith('lyricforge-separator.exe'),
    );
    expect(_argument(separator, '--provider'), 'auto');
    expect(_argument(separator, '--vocals-index'), '3');
    expect(
      _argument(separator, '--model'),
      endsWith('htdemucs_ft_vocals.onnx'),
    );

    // The decoded copy of the song is not kept next to the stems.
    expect(File(_argument(separator, '--input')).existsSync(), isFalse);
    expect(fixture.runDirectories(), hasLength(1));
  });

  test('reports separation progress as preprocessing', () async {
    final fixture = await _fixture();
    await fixture.run();
    expect(fixture.progress, isNotEmpty);
    expect(fixture.progress.map((p) => p.stage).toSet(), {
      TranscriptionStage.preprocessing,
    });
    final values = fixture.progress.map((p) => p.progress).toList();
    for (var i = 1; i < values.length; i++) {
      expect(values[i], greaterThanOrEqualTo(values[i - 1]));
    }
    expect(values.last, closeTo(1.0, 1e-9));
    expect(fixture.progress.first.message, contains('下载'));
    expect(fixture.progress.last.message, '正在分离人声 100%');
  });

  test('a failed install falls back without starting a process', () async {
    final fixture = await _fixture();
    fixture.runtime.error = const VocalSeparatorInstallException(
      '人声分离组件尚未发布',
      details: 'HTTP 404',
    );
    final result = await fixture.run();
    expect(result.outcome.status, VocalSeparationStatus.failed);
    expect(result.outcome.failure, VocalSeparationFailure.installFailed);
    expect(result.outcome.detail, contains('HTTP 404'));
    expect(result.updatedAudio, isNull);
    expect(fixture.processes.calls, isEmpty);
  });

  test('an unexpected install error is still only a fallback', () async {
    final fixture = await _fixture();
    fixture.runtime.error = StateError('disk full');
    final result = await fixture.run();
    expect(result.outcome.failure, VocalSeparationFailure.installFailed);
  });

  test('a song FFmpeg cannot decode falls back', () async {
    final fixture = await _fixture();
    fixture.processes.ffmpeg = (arguments, process) async {
      process.error('Invalid data found when processing input');
      process.finish(1);
    };
    final result = await fixture.run();
    expect(result.outcome.failure, VocalSeparationFailure.conversionFailed);
    expect(result.outcome.detail, contains('Invalid data'));
    expect(fixture.runDirectories(), isEmpty);
    expect(fixture.processes.calls, hasLength(1));
  });

  test('a separator error keeps its code and message', () async {
    final fixture = await _fixture();
    fixture.processes.separator = (arguments, process) async {
      process.emit('LF_STAGE load-model');
      process.emit('LF_ERROR 4 cannot load model on cpu: bad protobuf');
      process.finish(4);
    };
    final result = await fixture.run();
    expect(result.outcome.failure, VocalSeparationFailure.separatorFailed);
    expect(result.outcome.detail, contains('LF_ERROR 4'));
    expect(result.outcome.detail, contains('bad protobuf'));
    expect(fixture.runDirectories(), isEmpty);
  });

  test('exit code 0 without LF_DONE is not trusted', () async {
    final fixture = await _fixture();
    fixture.processes.separator = (arguments, process) async {
      await _writeStems(arguments);
      process.emit('LF_STAGE separate');
      process.finish(0);
    };
    final result = await fixture.run();
    expect(result.outcome.failure, VocalSeparationFailure.separatorFailed);
  });

  test('a missing stem after LF_DONE is invalid output', () async {
    final fixture = await _fixture();
    fixture.processes.separator = (arguments, process) async {
      process.emit('LF_DONE vocals=x');
      process.finish(0);
    };
    final result = await fixture.run();
    expect(result.outcome.failure, VocalSeparationFailure.invalidOutput);
  });

  test('an instrumental (near-silent stem) is recognised from the mix', () async {
    final fixture = await _fixture();
    fixture.processes.separator = (arguments, process) async {
      await _writeStems(arguments);
      process.emit('LF_PROVIDER cpu');
      process.emit(
        'LF_STATS mix_rms=0.2 vocals_rms=0.002 accompaniment_rms=0.2 seconds=3',
      );
      process.emit('LF_DONE vocals=x');
      process.finish(0);
    };
    final result = await fixture.run();
    expect(result.outcome.failure, VocalSeparationFailure.silentStem);
    expect(result.outcome.provider, 'cpu');
    expect(result.outcome.stats?.vocalsToMixRatio, closeTo(0.01, 1e-9));
    expect(result.updatedAudio, isNull);
    expect(fixture.runDirectories(), isEmpty);
  });

  test('a GPU fallback is reported with the CPU result', () async {
    final fixture = await _fixture();
    fixture.processes.separator = (arguments, process) async {
      await _writeStems(arguments);
      process.emit('LF_PROVIDER dml');
      process.emit('LF_FALLBACK dml failed during inference: E_OUTOFMEMORY');
      process.emit('LF_PROVIDER cpu');
      process.emit('LF_STATS mix_rms=0.2 vocals_rms=0.1 seconds=3');
      process.emit('LF_DONE vocals=x');
      process.finish(0);
    };
    final result = await fixture.run();
    expect(result.outcome.status, VocalSeparationStatus.separated);
    expect(result.outcome.provider, 'cpu');
    expect(result.outcome.fallbacks, [
      'dml failed during inference: E_OUTOFMEMORY',
    ]);
  });

  test('a separator that cannot start falls back', () async {
    final fixture = await _fixture();
    fixture.processes.startError = const ProcessException(
      'ffmpeg',
      [],
      'not found',
      2,
    );
    final result = await fixture.run();
    expect(result.outcome.failure, VocalSeparationFailure.conversionFailed);
    expect(fixture.runDirectories(), isEmpty);
  });

  test('cancelling during separation kills the process', () async {
    final fixture = await _fixture();
    final started = Completer<void>();
    fixture.processes.separator = (arguments, process) async {
      process.emit('LF_STAGE separate');
      started.complete();
    };
    final separator = fixture.separator();
    final run = fixture.run(using: separator);
    await started.future;
    await separator.cancel();
    await expectLater(run, _cancelled);
    expect(fixture.processes.last?.killed, isTrue);
    expect(fixture.runtime.cancels, 1);
    expect(fixture.runDirectories(), isEmpty);
  });

  test('cancelling during the download stops before any process', () async {
    final fixture = await _fixture();
    final separator = fixture.separator();
    fixture.runtime.error = const TranscriptionException.cancelled('已取消');
    await expectLater(fixture.run(using: separator), _cancelled);
    expect(fixture.processes.calls, isEmpty);
  });

  test('an unchanged automatic stem is reused without work', () async {
    final first = await _fixture();
    final separated = await first.run();
    final project = first.project.copyWith(audioAsset: separated.updatedAudio);
    first.processes.calls.clear();
    final again = await first.run(project: project);
    expect(again.outcome.status, VocalSeparationStatus.reused);
    expect(again.outcome.vocalPath, separated.outcome.vocalPath);
    expect(
      again.outcome.accompanimentPath,
      separated.outcome.accompanimentPath,
    );
    expect(again.outcome.provider, 'dml');
    expect(again.updatedAudio, isNull);
    expect(first.processes.calls, isEmpty);
    expect(first.runtime.installs, 1);
  });

  test('separating again prunes stems nobody points at', () async {
    final fixture = await _fixture();
    final stale = Directory('${fixture.workDirectory}/run-1');
    await stale.create(recursive: true);
    await File('${stale.path}/vocals.wav').writeAsString('old');
    final unrelated = Directory('${fixture.workDirectory}/keep-me');
    await unrelated.create(recursive: true);

    await fixture.run();
    expect(stale.existsSync(), isFalse);
    expect(unrelated.existsSync(), isTrue);
  });

  test('the stem the project still uses survives a new run', () async {
    final root = await Directory.systemTemp.createTemp('vocal-keep-');
    addTearDown(() => root.delete(recursive: true));
    final current = Directory('${root.path}/stems/run-5');
    await current.create(recursive: true);
    final vocal = File('${current.path}/vocals.wav');
    await vocal.writeAsString('current');
    final fixture = await _fixture(
      vocalPath: vocal.path,
      metadata: {
        VocalStemMarker.metadataKey: VocalStemMarker(
          separatorRevision: 'htdemucs-ft-vocals-onnx-v0',
          sourceFingerprint: 'stale',
          vocalPath: vocal.path,
          generatedAt: DateTime.utc(2026, 1, 1),
        ).toJson(),
      },
    );
    final separator = LocalProjectVocalSeparator(
      runtime: fixture.runtime,
      startProcess: fixture.processes.start,
    );
    final result = await separator.separate(
      fixture.project,
      config: _config,
      workDirectory: '${root.path}/stems',
      onProgress: (_) {},
    );
    expect(result.outcome.status, VocalSeparationStatus.separated);
    expect(current.existsSync(), isTrue);
  });

  test('skips are returned without touching the runtime', () async {
    final fixture = await _fixture();
    final off = await fixture.run(
      config: _config.copyWith(vocalSeparation: VocalSeparationPreference.off),
    );
    expect(off.outcome.skipReason, VocalSeparationSkipReason.disabled);

    fixture.runtime.supported = false;
    final unsupported = await fixture.run();
    expect(
      unsupported.outcome.skipReason,
      VocalSeparationSkipReason.unsupportedPlatform,
    );
    expect(fixture.runtime.installs, 0);
    expect(fixture.processes.calls, isEmpty);
  });

  test('a project without audio is skipped', () async {
    final fixture = await _fixture();
    final now = DateTime.utc(2026, 11, 18);
    final result = await fixture.run(
      project: ProjectManifest(
        id: 'empty',
        name: 'Empty',
        createdAt: now,
        updatedAt: now,
      ),
    );
    expect(result.outcome.skipReason, VocalSeparationSkipReason.sourceMissing);
  });

  test('the silent-stem threshold is about -30 dB', () {
    expect(LocalProjectVocalSeparator.silentStemRatio, closeTo(0.0316, 0.002));
    expect(VocalSeparationPlanner.maxDuration, const Duration(minutes: 15));
  });
}

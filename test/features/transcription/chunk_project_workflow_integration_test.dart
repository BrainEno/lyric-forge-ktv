import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/project_proofread_evidence.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_media_metadata.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_state.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/local_media_metadata_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_path_canonicalizer.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/project/data/repositories/file_project_repository.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/asr_evidence_audio_verifier.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/asr_process_supervisor.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/local_project_transcription_workflow.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/project_proofread_evidence_loader.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/resumable_chunked_transcription_service.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/chunked_independent_asr_evidence.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/independent_asr_evidence.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_resource_coordinator.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_runtime_manager.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_profile_resolver.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_service.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_settings_store.dart';

const _config = TranscriptionConfig(
  mode: TranscriptionMode.whisperOnly,
  whisperExecutable: 'whisper',
  modelPath: 'model',
);
const _profile = ResolvedTranscriptionProfile(
  profile: TranscriptionProfilePreference.custom,
  label: 'test',
  description: 'test',
  hardware: TranscriptionHardwareInfo(
    operatingSystem: 'linux',
    architecture: 'x86_64',
  ),
  config: _config,
);

// These tests cross actual chunk capture, workflow conditional writes, the
// file store and a newly constructed loader. The process and ASR boundaries are
// deterministic substitutes, not a test of real speech recognition.
void main() {
  late _Harness h;

  setUp(() async {
    h = await _Harness.create();
  });
  tearDown(() async => h.dispose());

  test('capture survives workflow save and a fresh repository', () async {
    await h.run();
    final saved = await h.reopen();
    expect(saved.status, ProjectStatus.editing);
    expect(saved.currentStage, ProcessingStage.transcriptionComplete);
    expect(saved.metadata.containsKey('activeTranscriptionRunId'), isFalse);
    expect(saved.lyricDocument!.metadata['editableDraft'], isTrue);
    expect(saved.lyricDocument!.metadata['timelineFormat'], 'lyricforge-timeline-v1');
    final evidence = ChunkedIndependentAsrEvidence.tryParse(
      saved.lyricDocument!.metadata[ChunkedIndependentAsrEvidence.metadataKey],
    );
    expect(evidence, isNotNull);
    expect(evidence!.sourceAudioSha256, sha256.convert(await h.source.readAsBytes()).toString());
    expect(evidence.chunks, hasLength(2));
    expect(evidence.chunks[0].start, Duration.zero);
    expect(evidence.chunks[0].end, const Duration(seconds: 3));
    expect(evidence.chunks[1].start, const Duration(seconds: 2));
    expect(evidence.chunks[1].end, const Duration(seconds: 4));
    expect(saved.lyricDocument!.metadata.containsKey(IndependentAsrEvidence.metadataKey), isFalse);
    expect(h.delegate.calls, 2);
    expect(h.ffmpeg.chunkStartRequests, 2);

    final before = jsonEncode(saved.toJson());
    final result = await h.load(saved);
    expect(result.status, ProjectProofreadEvidenceStatus.chunkAuditOnly);
    expect(result.primary, isNull);
    expect(result.secondary, isNull);
    expect(result.chunks, hasLength(2));
    expect(result.chunks[0].primary.lines.single.text, 'primary');
    expect(result.chunks[0].secondary.lines.single.text, 'secondary');
    expect(result.chunks[1].primary.lines.single.startTime, const Duration(seconds: 2));
    expect(result.chunks[1].secondary.lines.single.startTime, const Duration(milliseconds: 2500));
    expect(result.chunks[1].secondary.lines.single.endTime, const Duration(milliseconds: 3500));
    expect(result.chunks[0].primaryEngine, 'qwen3-asr-1.7b');
    expect(result.chunks[1].secondaryEngine, 'whisper.cpp-large-v3');
    expect(() => result.chunks.clear(), throwsUnsupportedError);
    expect(jsonEncode((await h.reopen()).toJson()), before);
  });

  test('repeated reopen and inspection never save the project', () async {
    await h.run();
    final first = await h.reopen();
    final initial = await h.store.readAsString();
    for (var i = 0; i < 3; i++) {
      final reopened = await h.reopen();
      final result = await h.load(reopened);
      expect(result.status, ProjectProofreadEvidenceStatus.chunkAuditOnly);
      expect(reopened.revision, first.revision);
      expect(await h.store.readAsString(), initial);
    }
  });

  test('editing the draft retains originals as audit only', () async {
    await h.run();
    final old = await h.current();
    final originalEvidence = old.lyricDocument!.metadata[ChunkedIndependentAsrEvidence.metadataKey];
    final updated = await h.repo.updateProject(old.copyWith(
      lyricDocument: old.lyricDocument!.copyWith(
        lines: _manual.lines,
        metadata: {...old.lyricDocument!.metadata, ..._manual.metadata},
      ),
      currentStage: ProcessingStage.lyricsEdited,
    ));
    final reopened = await h.reopen();
    expect(reopened.revision, updated.revision);
    expect(reopened.lyricDocument!.lines.single.text, 'manual edit');
    expect(reopened.lyricDocument!.metadata[ChunkedIndependentAsrEvidence.metadataKey], originalEvidence);
    final before = jsonEncode(reopened.toJson());
    final result = await h.load(reopened);
    expect(result.status, ProjectProofreadEvidenceStatus.chunkAuditOnly);
    expect(result.chunks[0].primary.lines.single.text, 'primary');
    expect(result.chunks[1].secondary.lines.single.text, 'secondary');
    expect(result.primary, isNull);
    expect(result.secondary, isNull);
    expect(jsonEncode((await h.reopen()).toJson()), before);
  });

  test('concurrent edit during actual chunk capture is not replaced', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    h.onChunk = (request, call) async {
      if (call == 1) {
        entered.complete();
        await release.future;
      }
    };
    final running = h.run();
    await entered.future;
    final inFlight = await h.current();
    expect(inFlight.status, ProjectStatus.transcribing);
    final latest = await h.repo.updateProject(inFlight.copyWith(
      lyricDocument: _manual,
      currentStage: ProcessingStage.lyricsEdited,
      metadata: {...inFlight.metadata, 'concurrent': 'preserved'},
    ));
    release.complete();
    await expectLater(running, throwsA(isA<TranscriptionException>().having(
      (e) => e.message, 'message', contains('未覆盖最新歌词'),
    )));
    final reopened = await h.reopen();
    expect(reopened.revision, greaterThan(latest.revision));
    expect(reopened.lyricDocument!.toJson(), _manual.toJson());
    expect(reopened.currentStage, ProcessingStage.lyricsEdited);
    expect(reopened.metadata['concurrent'], 'preserved');
    expect(reopened.metadata.containsKey('activeTranscriptionRunId'), isFalse);
    expect((await h.load(reopened)).status, ProjectProofreadEvidenceStatus.missingEvidence);
  });

  test('cancellation during chunk capture leaves original lyrics on disk', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    h.onChunk = (request, call) async {
      if (call == 1) {
        entered.complete();
        await release.future;
      }
    };
    final running = h.run();
    await entered.future;
    final cancel = h.workflow.cancel();
    release.complete();
    await cancel;
    await expectLater(running, throwsA(isA<TranscriptionException>().having(
      (e) => e.kind, 'kind', TranscriptionFailureKind.cancelled,
    )));
    final reopened = await h.reopen();
    expect(reopened.lyricDocument!.toJson(), _original.toJson());
    expect(reopened.status, ProjectStatus.editing);
    expect(reopened.metadata.containsKey('activeTranscriptionRunId'), isFalse);
    expect((await h.load(reopened)).status, ProjectProofreadEvidenceStatus.missingEvidence);
  });

  test('an incomplete independent pair saves a draft but no audit set', () async {
    h.includeEvidence = (call) => call == 1;
    await h.run();
    final reopened = await h.reopen();
    expect(reopened.lyricDocument!.lines, isNotEmpty);
    expect(reopened.lyricDocument!.metadata.containsKey(ChunkedIndependentAsrEvidence.metadataKey), isFalse);
    expect((await h.load(reopened)).status, ProjectProofreadEvidenceStatus.missingEvidence);
  });

  test('a changed source during capture cannot publish its audit set', () async {
    h.onChunk = (request, call) async {
      if (call == 2) await h.source.writeAsBytes(List<int>.filled(128, 9));
    };
    await h.run();
    final reopened = await h.reopen();
    expect(reopened.lyricDocument!.lines, isNotEmpty);
    expect(reopened.lyricDocument!.metadata.containsKey(ChunkedIndependentAsrEvidence.metadataKey), isFalse);
    expect((await h.load(reopened)).status, ProjectProofreadEvidenceStatus.missingEvidence);
  });

  test('replaced bytes after reopening reject otherwise valid evidence', () async {
    await h.run();
    final saved = await h.reopen();
    final before = jsonEncode(saved.toJson());
    await h.source.writeAsBytes(List<int>.filled(128, 8));
    final result = await h.load(saved);
    expect(result.status, ProjectProofreadEvidenceStatus.audioChanged);
    expect(result.chunks, isEmpty);
    expect(result.primary, isNull);
    expect(result.secondary, isNull);
    expect(jsonEncode((await h.reopen()).toJson()), before);
  });

  test('missing audio after reopening is unavailable', () async {
    await h.run();
    final saved = await h.reopen();
    await h.source.delete();
    final result = await h.load(saved);
    expect(result.status, ProjectProofreadEvidenceStatus.audioUnavailable);
    expect(result.chunks, isEmpty);
  });

  test('new preferred vocal stem is verified instead of the old source', () async {
    await h.run();
    final old = await h.current();
    final stem = File('${h.root.path}/vocal.wav');
    await stem.writeAsBytes(List<int>.filled(128, 3));
    await h.repo.updateProject(old.copyWith(audioAsset: old.audioAsset!.copyWith(vocalPath: stem.path)));
    final saved = await h.reopen();
    final result = await h.load(saved);
    expect(result.status, ProjectProofreadEvidenceStatus.audioChanged);
    expect(result.chunks, isEmpty);
  });

  test('revision changed after editor opened rejects old draft', () async {
    await h.run();
    final old = await h.reopen();
    final current = await h.current();
    await h.repo.updateProject(current.copyWith(name: 'new project name'));
    final freshRepo = FileProjectRepository(rootDirectory: h.root);
    final result = await VerifiedProjectProofreadEvidenceLoader(projects: freshRepo).load(
      projectId: h.id, expectedProjectRevision: old.revision, draft: old.lyricDocument!,
    );
    expect(result.status, ProjectProofreadEvidenceStatus.projectChanged);
    expect(result.chunks, isEmpty);
  });

  test('revision changed while hashing rejects the result', () async {
    await h.run();
    final saved = await h.current();
    final loader = VerifiedProjectProofreadEvidenceLoader(
      projects: h.repo,
      verifyAudio: ({required rawEvidence, required currentAudioPath}) async {
        final status = await const AsrEvidenceAudioVerifier().verify(
          rawEvidence: rawEvidence, currentAudioPath: currentAudioPath,
        );
        final current = await h.current();
        await h.repo.updateProject(current.copyWith(name: 'changed while hashing'));
        return status;
      },
    );
    final result = await loader.load(projectId: h.id, expectedProjectRevision: saved.revision, draft: saved.lyricDocument!);
    expect(result.status, ProjectProofreadEvidenceStatus.projectChanged);
    expect(result.chunks, isEmpty);
    expect((await h.reopen()).name, 'changed while hashing');
  });

  test('unsupported draft offset never exposes captured originals', () async {
    await h.run();
    final saved = await h.reopen();
    final result = await h.load(saved, draft: saved.lyricDocument!.copyWith(globalOffset: const Duration(milliseconds: 50)));
    expect(result.status, ProjectProofreadEvidenceStatus.unsupportedOffsets);
    expect(result.chunks, isEmpty);
  });

  final corruptions = <String, void Function(Map<String, dynamic>)>{
    'unsupported schema': (raw) => raw['schemaVersion'] = 42,
    'partial scope': (raw) => raw['scope'] = 'partial',
    'bad source digest': (raw) => raw['sourceAudioSha256'] = 'not-a-digest',
    'missing chunk': (raw) => (raw['chunks'] as List).removeLast(),
    'reordered chunks': (raw) {
      final chunks = raw['chunks'] as List;
      final first = chunks[0];
      chunks[0] = chunks[1];
      chunks[1] = first;
    },
    'wrong start time': (raw) => (raw['chunks'] as List)[1]['startMs'] = 2100,
    'wrong duration': (raw) => raw['durationMs'] = 5000,
    'invalid overlap': (raw) => raw['overlapMs'] = raw['chunkDurationMs'],
    'missing pair': (raw) => (raw['chunks'] as List)[1]['evidence'].remove('secondary'),
    'invalid engine': (raw) => (raw['chunks'] as List)[1]['evidence']['secondary']['engine'] = 'unknown',
    'empty transcript': (raw) => (raw['chunks'] as List)[0]['evidence']['primary']['lines'] = [],
  };
  for (final entry in corruptions.entries) {
    test('persisted ${entry.key} fails closed after reopening', () async {
      await h.run();
      final saved = await h.current();
      final document = saved.lyricDocument!;
      final raw = jsonDecode(jsonEncode(document.metadata[ChunkedIndependentAsrEvidence.metadataKey])) as Map<String, dynamic>;
      entry.value(raw);
      await h.repo.updateProject(saved.copyWith(lyricDocument: document.copyWith(
        metadata: {...document.metadata, ChunkedIndependentAsrEvidence.metadataKey: raw},
      )));
      final reopened = await h.reopen();
      final before = jsonEncode(reopened.toJson());
      final result = await h.load(reopened);
      expect(result.status, ProjectProofreadEvidenceStatus.invalidEvidence);
      expect(result.chunks, isEmpty);
      expect(result.primary, isNull);
      expect(result.secondary, isNull);
      expect(jsonEncode((await h.reopen()).toJson()), before);
    });
  }
}

const _original = LyricDocument(
  language: 'en',
  lines: [LyricLine(id: 'original', text: 'original lyric', startTime: Duration.zero, endTime: Duration(seconds: 1))],
  metadata: {'owner': 'user'},
);
const _manual = LyricDocument(
  language: 'en',
  lines: [LyricLine(id: 'manual', text: 'manual edit', startTime: Duration.zero, endTime: Duration(seconds: 1))],
  metadata: {'manuallyEditedLineIds': ['manual']},
);

class _Harness {
  _Harness(this.root, this.source, this.repo, this.id, this.ffmpeg);
  final Directory root;
  final File source;
  final FileProjectRepository repo;
  final String id;
  final _FfmpegStub ffmpeg;
  late final _AsyncService delegate;
  late final ResumableChunkedTranscriptionService chunks;
  late final LocalProjectTranscriptionWorkflow workflow;
  Future<void> Function(TranscriptionRequest, int)? onChunk;
  bool Function(int)? includeEvidence;
  File get store => File('${root.path}/projects.json');

  static Future<_Harness> create() async {
    final root = await Directory.systemTemp.createTemp('full-chunk-project-');
    final source = File('${root.path}/source.wav');
    await source.writeAsBytes(List<int>.filled(128, 7));
    final repo = FileProjectRepository(rootDirectory: root);
    final created = await repo.createProject(name: 'song');
    await repo.updateProject(created.copyWith(
      projectDirectory: root.path,
      audioAsset: AudioAsset(originalPath: source.path, format: 'wav'),
      lyricDocument: _original,
      status: ProjectStatus.editing,
      currentStage: ProcessingStage.lyricsEdited,
    ));
    final harness = _Harness(root, source, repo, created.id, _FfmpegStub(durationLabel: '00:00:04.000'));
    harness.delegate = _AsyncService((request, service) async {
      await harness.onChunk?.call(request, service.calls);
      return _chunkEvidenceResult(request, includeEvidence: harness.includeEvidence?.call(service.calls) ?? true);
    });
    harness.chunks = ResumableChunkedTranscriptionService(
      delegate: harness.delegate,
      chunkDuration: const Duration(seconds: 3),
      overlap: const Duration(seconds: 1),
      maxAttempts: 1,
      processSupervisor: harness.ffmpeg.supervisor,
    );
    harness.workflow = LocalProjectTranscriptionWorkflow(
      projectRepository: repo,
      transcriptionService: harness.chunks,
      settingsStore: _Settings(null),
      profileResolver: _Resolver(),
      runtimeManager: _Runtime(),
      resources: AsrResourceCoordinator(),
      mediaMetadataRepository: _UnusedMetadata(),
      playbackSession: _UnusedPlayback(),
      pathCanonicalizer: _UnusedCanonicalizer(),
    );
    return harness;
  }

  Future<void> run() => workflow.transcribeProject(id);
  Future<ProjectManifest> current() async => (await repo.getProjectById(id))!;
  Future<ProjectManifest> reopen() async => (await FileProjectRepository(rootDirectory: root).getProjectById(id))!;
  Future<ProjectProofreadEvidenceResult> load(ProjectManifest project, {LyricDocument? draft}) =>
      VerifiedProjectProofreadEvidenceLoader(projects: FileProjectRepository(rootDirectory: root)).load(
        projectId: id, expectedProjectRevision: project.revision, draft: draft ?? project.lyricDocument!,
      );
  Future<void> dispose() async {
    await chunks.dispose();
    await root.delete(recursive: true);
  }
}

class _FfmpegStub {
  _FfmpegStub({required this.durationLabel});

  final String durationLabel;
  int chunkStartRequests = 0;

  AsrProcessSupervisor get supervisor => AsrProcessSupervisor(
    startProcess: (_, arguments) async {
      final process = _FakeProcess();
      if (arguments.contains('-ss')) {
        chunkStartRequests++;
        await File(arguments.last).writeAsBytes(List<int>.filled(128, 0));
        Timer(const Duration(milliseconds: 1), () => process.finish(0));
      } else {
        Timer(const Duration(milliseconds: 1), () {
          process.emitStderr(
            'Duration: $durationLabel, start: 0.000000, bitrate: 1 kb/s',
          );
          process.finish(0);
        });
      }
      return process;
    },
    streamDrainGrace: const Duration(milliseconds: 10),
  );
}

class _AsyncService implements TranscriptionService {
  _AsyncService(this.run);

  final Future<TranscriptionResult> Function(
    TranscriptionRequest,
    _AsyncService,
  )
  run;
  final _controller = StreamController<TranscriptionProgress>.broadcast();
  int calls = 0;

  void emit(TranscriptionProgress event) => _controller.add(event);

  @override
  Stream<TranscriptionProgress> get progressStream => _controller.stream;
  @override
  bool get isRunning => false;
  @override
  Future<TranscriptionResult> transcribe(TranscriptionRequest request) {
    calls++;
    return run(request, this);
  }

  @override
  Future<void> cancel() async {}
  @override
  Future<void> dispose() => _controller.close();
}

class _FakeProcess implements Process {
  final StreamController<List<int>> _stdout = StreamController<List<int>>();
  final StreamController<List<int>> _stderr = StreamController<List<int>>();
  final Completer<int> _exitCode = Completer<int>();
  final IOSink _stdin = IOSink(_DiscardingConsumer());
  final List<ProcessSignal> killSignals = <ProcessSignal>[];
  final bool killOnSigterm;
  final bool killOnSigkill;

  _FakeProcess({this.killOnSigterm = true, this.killOnSigkill = true});

  @override
  IOSink get stdin => _stdin;

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  int get pid => 12345;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killSignals.add(signal);
    if ((signal == ProcessSignal.sigterm && killOnSigterm) ||
        (signal == ProcessSignal.sigkill && killOnSigkill)) {
      finish(137);
    }
    return true;
  }

  void emitStderr(String text) => _stderr.add(utf8.encode(text));

  void finish(int code) {
    if (!_exitCode.isCompleted) _exitCode.complete(code);
    unawaited(_closeStreams());
  }

  Future<void> _closeStreams() async {
    if (!_stdout.isClosed) await _stdout.close();
    if (!_stderr.isClosed) await _stderr.close();
  }
}

class _DiscardingConsumer implements StreamConsumer<List<int>> {
  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await stream.drain<void>();
  }

  @override
  Future<void> close() async {}
}

Future<TranscriptionResult> _chunkEvidenceResult(
  TranscriptionRequest request, {
  bool includeEvidence = true,
  String? hashOverride,
  bool badTimes = false,
  bool badEngine = false,
}) async {
  final hash =
      hashOverride ??
      sha256
          .convert(await File(request.inputAudioPath).readAsBytes())
          .toString();
  final primary = LyricDocument(
    language: 'en',
    lines: [
      LyricLine(
        text: 'primary',
        startTime: Duration.zero,
        endTime: badTimes
            ? const Duration(seconds: 10)
            : const Duration(seconds: 1),
      ),
    ],
  );
  final secondary = LyricDocument(
    language: 'en',
    lines: [
      LyricLine(
        text: 'secondary',
        startTime: const Duration(milliseconds: 500),
        endTime: const Duration(milliseconds: 1500),
      ),
    ],
  );
  final proof = IndependentAsrEvidence(
    capturedAt: DateTime.utc(2026, 11, 7),
    sourceAudioSha256: hash,
    primary: IndependentAsrTranscript(
      engine: 'qwen3-asr-1.7b',
      document: primary,
    ),
    secondary: IndependentAsrTranscript(
      engine: badEngine ? 'unknown' : 'whisper.cpp-large-v3',
      document: secondary,
    ),
  );
  return TranscriptionResult(
    lyrics: primary.copyWith(
      metadata: {
        if (includeEvidence) IndependentAsrEvidence.metadataKey: proof.toJson(),
        ChunkedIndependentAsrEvidence.metadataKey: {'scope': 'forged'},
      },
    ),
    normalizedAudioPath: request.inputAudioPath,
    rawJsonPath: '${request.outputDirectory}/raw.json',
    detectedLanguage: 'en',
  );
}

class _Settings implements TranscriptionSettingsStore {
  _Settings(this.onLoad);
  final Future<void> Function()? onLoad;
  @override
  Future<TranscriptionConfig?> load() async {
    await onLoad?.call();
    return _config;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Resolver implements TranscriptionProfileResolver {
  @override
  Future<ResolvedTranscriptionProfile> resolve(
    TranscriptionConfig config,
  ) async => _profile;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Runtime implements AsrRuntimeManager {
  @override
  Future<TranscriptionConfig> repair(TranscriptionConfig config) async =>
      config;
  @override
  Future<AsrRuntimeStatus> inspect(TranscriptionConfig config) async =>
      const AsrRuntimeStatus(
        profile: _profile,
        components: [],
        managedRoot: '',
      );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedMetadata implements LocalMediaMetadataRepository {
  @override
  Future<LocalMediaMetadata?> getForAudio(String sourcePath) async => null;
  @override
  Future<LocalMediaMetadata> save(LocalMediaMetadata metadata) async =>
      metadata;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedPlayback implements PlaybackSessionService {
  @override
  PlaybackSessionState get currentState => const PlaybackSessionState();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedCanonicalizer implements AudioPathCanonicalizer {
  @override
  String canonicalize(String path) => path;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

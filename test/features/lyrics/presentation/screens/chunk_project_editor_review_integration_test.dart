import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/data/services/local_lyric_file_import_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/forced_alignment_proofread_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_file_export_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/controllers/lyric_editor_document_controller.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/lyric_editor_dependencies.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/screens/lyric_editor_screen.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/project_asr_snapshot_dialog.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/project_chunk_asr_snapshot_dialog.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_media_metadata.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_state.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/local_media_metadata_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_path_canonicalizer.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_player_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/project/data/repositories/file_project_repository.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/asr_evidence_audio_verifier.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/asr_process_supervisor.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/high_quality_transcription_service.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/local_project_transcription_workflow.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/project_proofread_evidence_loader.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/resumable_chunked_transcription_service.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/chunked_independent_asr_evidence.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_resource_coordinator.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_runtime_manager.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_profile_resolver.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_service.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_settings_store.dart';
import 'package:provider/provider.dart';

const _config = TranscriptionConfig(
  mode: TranscriptionMode.highestQuality,
  qwenExecutable: 'qwen',
  whisperExecutable: 'whisper',
  modelPath: 'ggml-large-v3.bin',
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

void main() {
  testWidgets(
    'captured chunk audit survives disk reopen into read-only editor dialogs',
    (tester) async {
      final fixture = await _DiskChunkFixture.capture(tester);
      addTearDown(fixture.dispose);

      var alignmentCalls = 0;
      final reopenedRepo = FileProjectRepository(rootDirectory: fixture.root);
      final beforeDisk = await tester.runAsync(fixture.store.readAsString);

      final editor = await _mountEditor(
        tester,
        repository: reopenedRepo,
        projectId: fixture.projectId,
        runner:
            ({
              required audioPath,
              required text,
              required language,
              required audioDuration,
            }) async {
              alignmentCalls++;
              return const [];
            },
      );

      // Editable draft deduplicated overlap while keeping all 4 merged lines.
      expect(
        editor.document!.lines.map((l) => l.text).toList(),
        ['opening verse', 'shared chorus', 'ending refrain', 'whisper adlib'],
      );
      expect(editor.hasChanges, isFalse);

      await _requestProjectEvidenceInEditor(tester);
      await _waitForFinder(
        tester,
        find.byType(ProjectChunkAsrSnapshotDialog),
        description: 'chunk snapshot list dialog',
      );

      expect(find.text('分片原始双引擎快照（只读）'), findsOneWidget);
      expect(find.textContaining('重叠区可能重复'), findsOneWidget);
      expect(find.textContaining('不比较当前歌词'), findsOneWidget);
      expect(find.text('共 2 个分片，时间为完整音源的绝对时间。'), findsOneWidget);
      expect(find.text('00:00.000 – 00:03.000'), findsOneWidget);
      expect(find.text('00:02.000 – 00:04.000'), findsOneWidget);

      // Chunk 1 keeps the overlapping chorus before closing back to the list.
      await tester.tap(find.text('分片 1'));
      await tester.pumpAndSettle();
      expect(find.byType(ProjectAsrSnapshotDialog), findsOneWidget);
      expect(find.text('分片 1 原始快照（只读）'), findsOneWidget);
      expect(find.text('主稿第 2 行：shared chorus'), findsOneWidget);
      await tester.tap(find.text('关闭').last);
      await tester.pumpAndSettle();

      // Chunk 2 preserves overlap in global time plus the secondary-only adlib.
      await tester.tap(find.text('分片 2'));
      await tester.pumpAndSettle();
      expect(find.text('分片 2 原始快照（只读）'), findsOneWidget);
      expect(find.text('主稿第 1 行：shared chorus'), findsOneWidget);
      expect(find.text('仅第二引擎有此时间段'), findsOneWidget);
      expect(find.text('第二稿第 3 行：whisper adlib'), findsOneWidget);

      await tester.tap(find.text('主引擎原稿'));
      await tester.pumpAndSettle();
      expect(find.text('引擎：qwen3-asr-1.7b · 语言：en'), findsOneWidget);
      expect(
        find.text('第 1 行 · 00:02.100 – 00:02.900 · 置信度 95'),
        findsOneWidget,
      );
      expect(
        find.text('第 2 行 · 00:03.000 – 00:03.700 · 置信度 90'),
        findsOneWidget,
      );

      await tester.tap(find.text('第二引擎原稿'));
      await tester.pumpAndSettle();
      expect(find.text('引擎：whisper.cpp-large-v3 · 语言：en'), findsOneWidget);
      expect(
        find.text('第 3 行 · 00:03.750 – 00:03.950 · 置信度 80'),
        findsOneWidget,
      );

      await tester.tap(find.text('关闭').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();

      expect(find.byType(ProjectChunkAsrSnapshotDialog), findsNothing);
      expect(alignmentCalls, 0);
      expect(editor.hasChanges, isFalse);
      expect(await tester.runAsync(fixture.store.readAsString), beforeDisk);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'editing and deleting lines, saving, and reopening preserves read-only chunks',
    (tester) async {
      final fixture = await _DiskChunkFixture.capture(tester);
      addTearDown(fixture.dispose);

      final repoA = FileProjectRepository(rootDirectory: fixture.root);
      final editorA = await _mountEditor(
        tester,
        repository: repoA,
        projectId: fixture.projectId,
      );

      // Edit row 0 and delete row 1 (which clears indexed review metadata).
      final lyricField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == '歌词文本',
      );
      tester.widget<TextField>(lyricField).onChanged?.call('user edited verse');
      await tester.pumpAndSettle();
      await tester.tap(find.text('shared chorus').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('删除这一行'));
      await tester.tap(find.text('删除这一行'));
      await tester.pumpAndSettle();
      expect(editorA.hasChanges, isTrue);

      await tester.tap(find.widgetWithText(FilledButton, '保存修改'));
      await _waitForFinder(
        tester,
        find.text('歌词已保存'),
        description: 'saved snackbar',
      );
      expect(editorA.hasChanges, isFalse);

      // Reopen in a fresh repository and mount a new editor instance.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      final repoB = FileProjectRepository(rootDirectory: fixture.root);
      final editorB = await _mountEditor(
        tester,
        repository: repoB,
        projectId: fixture.projectId,
      );
      expect(
        editorB.document!.lines.map((l) => l.text).toList(),
        ['user edited verse', 'ending refrain', 'whisper adlib'],
      );

      await _requestProjectEvidenceInEditor(tester);
      await _waitForFinder(
        tester,
        find.byType(ProjectChunkAsrSnapshotDialog),
        description: 'chunk dialog after reopen',
      );

      await tester.tap(find.text('分片 1'));
      await tester.pumpAndSettle();
      // Both unedited originals remain intact despite draft edit/deletion.
      expect(find.text('主稿第 1 行：opening verse'), findsOneWidget);
      expect(find.text('主稿第 2 行：shared chorus'), findsOneWidget);
      await tester.tap(find.text('关闭').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();

      expect(
        editorB.document!.lines.map((l) => l.text).toList(),
        ['user edited verse', 'ending refrain', 'whisper adlib'],
      );
      expect(editorB.hasChanges, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'replaced source bytes or attached vocal stem fail closed in editor',
    (tester) async {
      final fixture = await _DiskChunkFixture.capture(tester);
      addTearDown(fixture.dispose);

      final repo = FileProjectRepository(rootDirectory: fixture.root);
      await _mountEditor(
        tester,
        repository: repo,
        projectId: fixture.projectId,
      );

      await tester.runAsync(
        () => fixture.source.writeAsBytes(List<int>.filled(128, 9)),
      );
      await _requestProjectEvidenceInEditor(tester);
      await _waitForFinder(
        tester,
        find.textContaining('识别音频与快照不一致'),
        description: 'audio changed snackbar',
      );
      expect(find.byType(ProjectChunkAsrSnapshotDialog), findsNothing);

      // Restore source bytes, attach a different preferred vocal stem, reload.
      await tester.runAsync(() async {
        await fixture.source.writeAsBytes(List<int>.filled(128, 7));
        final stem = File('${fixture.root.path}/vocal.wav');
        await stem.writeAsBytes(List<int>.filled(128, 4));
        final current = (await repo.getProjectById(fixture.projectId))!;
        await repo.updateProject(
          current.copyWith(
            audioAsset: current.audioAsset!.copyWith(vocalPath: stem.path),
          ),
        );
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      final repoAfterStem = FileProjectRepository(rootDirectory: fixture.root);
      await _mountEditor(
        tester,
        repository: repoAfterStem,
        projectId: fixture.projectId,
      );
      await _requestProjectEvidenceInEditor(tester);
      await _waitForFinder(
        tester,
        find.textContaining('识别音频与快照不一致'),
        description: 'stem changed snackbar',
      );
      expect(find.byType(ProjectChunkAsrSnapshotDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'stale editor revision rejects chunks, then save-conflict reload recovers',
    (tester) async {
      final fixture = await _DiskChunkFixture.capture(tester);
      addTearDown(fixture.dispose);

      final repo = FileProjectRepository(rootDirectory: fixture.root);
      final editor = await _mountEditor(
        tester,
        repository: repo,
        projectId: fixture.projectId,
      );

      // Another operation bumps revision on the shared repository.
      await tester.runAsync(() async {
        final current = (await repo.getProjectById(fixture.projectId))!;
        await repo.updateProject(current.copyWith(name: 'renamed elsewhere'));
      });

      await _requestProjectEvidenceInEditor(tester);
      await _waitForFinder(
        tester,
        find.textContaining('工程已在其他位置更新'),
        description: 'stale revision snackbar',
      );
      expect(find.byType(ProjectChunkAsrSnapshotDialog), findsNothing);

      // Attempt save to trigger conflict dialog, then reload latest revision.
      final lyricField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == '歌词文本',
      );
      tester.widget<TextField>(lyricField).onChanged?.call('unsaved draft');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '保存修改'));
      await _waitForFinder(
        tester,
        find.text('工程已在其他位置更新'),
        description: 'save conflict dialog',
      );

      await tester.tap(find.text('重新载入最新版'));
      await _waitForFinder(
        tester,
        find.text('已载入最新版工程。'),
        description: 'reloaded snackbar',
      );
      expect(editor.document!.lines.first.text, 'opening verse');
      expect(editor.hasChanges, isFalse);

      // Now the editor holds the current revision and chunk audit opens safely.
      await _requestProjectEvidenceInEditor(tester);
      await _waitForFinder(
        tester,
        find.byType(ProjectChunkAsrSnapshotDialog),
        description: 'chunk dialog after reload',
      );
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'in-memory edit while hashing audio discards stale chunk snapshot dialog',
    (tester) async {
      final fixture = await _DiskChunkFixture.capture(tester);
      addTearDown(fixture.dispose);

      final repo = FileProjectRepository(rootDirectory: fixture.root);
      final hashStarted = Completer<void>();
      final releaseHash = Completer<void>();
      final loader = VerifiedProjectProofreadEvidenceLoader(
        projects: repo,
        verifyAudio: ({required rawEvidence, required currentAudioPath}) async {
          hashStarted.complete();
          await releaseHash.future;
          return const AsrEvidenceAudioVerifier().verify(
            rawEvidence: rawEvidence,
            currentAudioPath: currentAudioPath,
          );
        },
      );

      final editor = await _mountEditor(
        tester,
        repository: repo,
        projectId: fixture.projectId,
        evidenceLoader: loader.load,
      );

      await _requestProjectEvidenceInEditor(tester);
      for (var i = 0; i < 60 && !hashStarted.isCompleted; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(hashStarted.isCompleted, isTrue);

      editor.updateLine(
        0,
        editor.document!.lines.first.copyWith(text: 'edited during verify'),
      );
      await tester.pump();
      releaseHash.complete();

      await _waitForFinder(
        tester,
        find.textContaining('原提案已丢弃'),
        description: 'stale in-memory edit snackbar',
      );
      expect(find.byType(ProjectChunkAsrSnapshotDialog), findsNothing);
      expect(editor.document!.lines.first.text, 'edited during verify');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'non-zero draft globalOffset fails closed for chunk audit in editor',
    (tester) async {
      final fixture = await _DiskChunkFixture.capture(tester);
      addTearDown(fixture.dispose);

      final repo = FileProjectRepository(rootDirectory: fixture.root);
      await _mountEditor(
        tester,
        repository: repo,
        projectId: fixture.projectId,
      );

      await tester.tap(find.textContaining('偏移'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('延后 100ms'));
      await tester.pumpAndSettle();

      await _requestProjectEvidenceInEditor(tester);
      await _waitForFinder(
        tester,
        find.textContaining('带有偏移，暂不能安全比较工程证据'),
        description: 'unsupported offset snackbar',
      );
      expect(find.byType(ProjectChunkAsrSnapshotDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'degraded chunk run exposes no chunk dialog and keeps editable draft',
    (tester) async {
      final fixture = await _DiskChunkFixture.capture(tester, failQwenOnCall: 2);
      addTearDown(fixture.dispose);

      final repo = FileProjectRepository(rootDirectory: fixture.root);
      final editor = await _mountEditor(
        tester,
        repository: repo,
        projectId: fixture.projectId,
      );
      expect(editor.document!.lines, isNotEmpty);

      await _requestProjectEvidenceInEditor(tester);
      await _waitForFinder(
        tester,
        find.textContaining('工程没有完整的独立双引擎快照'),
        description: 'missing evidence snackbar',
      );
      expect(find.byType(ProjectChunkAsrSnapshotDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<LyricEditorDocumentController> _mountEditor(
  WidgetTester tester, {
  required FileProjectRepository repository,
  required String projectId,
  ForcedAlignmentRunner? runner,
  ProjectProofreadEvidenceLoader? evidenceLoader,
}) async {
  tester.view.physicalSize = const Size(1600, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: LyricEditorScreen(
        projectId: projectId,
        dependencies: LyricEditorDependencies(
          projectRepository: repository,
          playbackSession: _FakePlaybackSession(),
          audioPlayer: _FakeAudioPlayer(),
          lyricFileExport: _FakeLyricFileExport(),
          lyricFileImport: LocalLyricFileImportService(),
          forcedAlignmentRunner:
              runner ??
              ({
                required audioPath,
                required text,
                required language,
                required audioDuration,
              }) async => const [],
          projectProofreadEvidenceLoader:
              evidenceLoader ??
              VerifiedProjectProofreadEvidenceLoader(projects: repository).load,
        ),
      ),
    ),
  );

  final lyricField = find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == '歌词文本',
  );
  await _waitForFinder(tester, lyricField, description: 'loaded lyric editor');
  return Provider.of<LyricEditorDocumentController>(
    tester.element(lyricField),
    listen: false,
  );
}

Future<void> _requestProjectEvidenceInEditor(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.spellcheck_rounded).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('智能校对 V2'));
  await tester.pumpAndSettle();
  final toggle = find.byKey(const ValueKey('project_asr_evidence_toggle'));
  await tester.ensureVisible(toggle);
  await tester.tap(toggle);
  await tester.tap(find.text('继续'));
  await tester.pump();
}

Future<void> _waitForFinder(
  WidgetTester tester,
  Finder finder, {
  required String description,
}) async {
  for (var i = 0; i < 60; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $description');
}

class _DiskChunkFixture {
  _DiskChunkFixture(this.root, this.source, this.projectId);

  final Directory root;
  final File source;
  final String projectId;
  File get store => File('${root.path}/projects.json');

  static Future<_DiskChunkFixture> capture(
    WidgetTester tester, {
    int? failQwenOnCall,
  }) async {
    late _DiskChunkFixture fixture;
    await tester.runAsync(() async {
      final root = await Directory.systemTemp.createTemp(
        'chunk-editor-integration-',
      );
      final source = File('${root.path}/source.wav');
      await source.writeAsBytes(List<int>.filled(128, 7));

      final repo = FileProjectRepository(rootDirectory: root);
      final created = await repo.createProject(name: 'Chunk Song');
      await repo.updateProject(
        created.copyWith(
          projectDirectory: root.path,
          audioAsset: AudioAsset(
            originalPath: source.path,
            format: 'wav',
            duration: const Duration(seconds: 4),
          ),
          status: ProjectStatus.draft,
          currentStage: ProcessingStage.audioImported,
        ),
      );

      final ffmpeg = _FfmpegStub(durationLabel: '00:00:04.000');
      var qwenCalls = 0;
      var whisperCalls = 0;
      final qwen = _ScriptedAsr((request) async {
        qwenCalls++;
        if (failQwenOnCall == qwenCalls) {
          throw const TranscriptionException.unknown('qwen runtime failed');
        }
        final lines = qwenCalls == 1
            ? const [
                LyricLine(
                  text: 'opening verse',
                  startTime: Duration(milliseconds: 100),
                  endTime: Duration(milliseconds: 1100),
                  confidence: 92,
                ),
                LyricLine(
                  text: 'shared chorus',
                  startTime: Duration(milliseconds: 2100),
                  endTime: Duration(milliseconds: 2900),
                  confidence: 85,
                ),
              ]
            : const [
                LyricLine(
                  text: 'shared chorus',
                  startTime: Duration(milliseconds: 100),
                  endTime: Duration(milliseconds: 900),
                  confidence: 95,
                ),
                LyricLine(
                  text: 'ending refrain',
                  startTime: Duration(milliseconds: 1000),
                  endTime: Duration(milliseconds: 1700),
                  confidence: 90,
                ),
              ];
        return TranscriptionResult(
          lyrics: LyricDocument(language: 'en', lines: lines),
          normalizedAudioPath:
              request.normalizedInputAudioPath ?? request.inputAudioPath,
          rawJsonPath: '${request.outputDirectory}/qwen.json',
          detectedLanguage: 'en',
        );
      });
      final whisper = _ScriptedAsr((request) async {
        whisperCalls++;
        final lines = whisperCalls == 1
            ? const [
                LyricLine(
                  text: 'opening words',
                  startTime: Duration(milliseconds: 100),
                  endTime: Duration(milliseconds: 1100),
                  confidence: 80,
                ),
                LyricLine(
                  text: 'shared chorus alt',
                  startTime: Duration(milliseconds: 2100),
                  endTime: Duration(milliseconds: 2900),
                  confidence: 75,
                ),
              ]
            : const [
                LyricLine(
                  text: 'shared chorus alt',
                  startTime: Duration(milliseconds: 100),
                  endTime: Duration(milliseconds: 900),
                  confidence: 75,
                ),
                LyricLine(
                  text: 'ending words',
                  startTime: Duration(milliseconds: 1000),
                  endTime: Duration(milliseconds: 1700),
                  confidence: 70,
                ),
                LyricLine(
                  text: 'whisper adlib',
                  startTime: Duration(milliseconds: 1750),
                  endTime: Duration(milliseconds: 1950),
                  confidence: 80,
                ),
              ];
        return TranscriptionResult(
          lyrics: LyricDocument(language: 'en', lines: lines),
          normalizedAudioPath:
              request.normalizedInputAudioPath ?? request.inputAudioPath,
          rawJsonPath: '${request.outputDirectory}/whisper.json',
          detectedLanguage: 'en',
        );
      });

      final service = ResumableChunkedTranscriptionService(
        delegate: HighQualityTranscriptionService(
          primary: qwen,
          fallback: whisper,
          processSupervisor: ffmpeg.supervisor,
        ),
        chunkDuration: const Duration(seconds: 3),
        overlap: const Duration(seconds: 1),
        maxAttempts: 1,
        processSupervisor: ffmpeg.supervisor,
      );
      try {
        final workflow = LocalProjectTranscriptionWorkflow(
          projectRepository: repo,
          transcriptionService: service,
          settingsStore: _Settings(),
          profileResolver: _Resolver(),
          runtimeManager: _Runtime(),
          resources: AsrResourceCoordinator(),
          mediaMetadataRepository: _UnusedMetadata(),
          playbackSession: _FakePlaybackSession(),
          pathCanonicalizer: _UnusedCanonicalizer(),
        );
        await workflow.transcribeProject(created.id);
      } finally {
        await service.dispose();
      }

      if (failQwenOnCall == null) {
        final saved = (await FileProjectRepository(
          rootDirectory: root,
        ).getProjectById(created.id))!;
        expect(
          ChunkedIndependentAsrEvidence.tryParse(
            saved.lyricDocument!.metadata[ChunkedIndependentAsrEvidence
                .metadataKey],
          ),
          isNotNull,
        );
      }

      fixture = _DiskChunkFixture(root, source, created.id);
    });
    return fixture;
  }

  Future<void> dispose() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  }
}

class _FfmpegStub {
  _FfmpegStub({required this.durationLabel});

  final String durationLabel;
  int _counter = 0;

  AsrProcessSupervisor get supervisor => AsrProcessSupervisor(
    startProcess: (_, arguments) async {
      final process = _FakeProcess();
      if (arguments.contains('-vn')) {
        _counter++;
        await File(arguments.last).writeAsBytes(List<int>.filled(128, _counter));
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

class _ScriptedAsr implements TranscriptionService {
  _ScriptedAsr(this.run);

  final Future<TranscriptionResult> Function(TranscriptionRequest) run;
  final _controller = StreamController<TranscriptionProgress>.broadcast();

  @override
  Stream<TranscriptionProgress> get progressStream => _controller.stream;

  @override
  bool get isRunning => false;

  @override
  Future<TranscriptionResult> transcribe(TranscriptionRequest request) =>
      run(request);

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
    if (signal == ProcessSignal.sigterm || signal == ProcessSignal.sigkill) {
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

class _Settings implements TranscriptionSettingsStore {
  @override
  Future<TranscriptionConfig?> load() async => _config;

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
        components: [
          AsrRuntimeComponentStatus(
            component: AsrRuntimeComponent.ffmpeg,
            state: AsrRuntimeComponentState.ready,
            label: 'FFmpeg',
            detail: 'ready',
          ),
          AsrRuntimeComponentStatus(
            component: AsrRuntimeComponent.whisperRuntime,
            state: AsrRuntimeComponentState.ready,
            label: 'Whisper',
            detail: 'ready',
          ),
          AsrRuntimeComponentStatus(
            component: AsrRuntimeComponent.whisperModel,
            state: AsrRuntimeComponentState.ready,
            label: 'Whisper Model',
            detail: 'ready',
          ),
          AsrRuntimeComponentStatus(
            component: AsrRuntimeComponent.qwenRuntime,
            state: AsrRuntimeComponentState.ready,
            label: 'Qwen',
            detail: 'ready',
          ),
          AsrRuntimeComponentStatus(
            component: AsrRuntimeComponent.qwenModel,
            state: AsrRuntimeComponentState.ready,
            label: 'Qwen Model',
            detail: 'ready',
          ),
          AsrRuntimeComponentStatus(
            component: AsrRuntimeComponent.qwenAligner,
            state: AsrRuntimeComponentState.ready,
            label: 'Qwen Aligner',
            detail: 'ready',
          ),
        ],
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

class _UnusedCanonicalizer implements AudioPathCanonicalizer {
  @override
  String canonicalize(String path) => path;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAudioPlayer implements AudioPlayerService {
  @override
  PlaybackState get currentState => const PlaybackState.idle();

  @override
  Stream<PlaybackState> get stateStream => const Stream.empty();

  @override
  Stream<Duration> get positionStream => const Stream.empty();

  @override
  Stream<Duration?> get durationStream => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePlaybackSession implements PlaybackSessionService {
  @override
  PlaybackSessionState get currentState => const PlaybackSessionState();

  @override
  Stream<PlaybackSessionState> get stateStream => const Stream.empty();

  @override
  PlaybackState get playbackState => const PlaybackState.idle();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLyricFileExport implements LyricFileExportService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

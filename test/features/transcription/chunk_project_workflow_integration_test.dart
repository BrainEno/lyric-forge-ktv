import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/app/lyric_editor_assembly.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/forced_alignment_proofread_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/project_proofread_evidence.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_media_metadata.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/local_media_metadata_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_path_canonicalizer.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/project/data/repositories/file_project_repository.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/asr_evidence_audio_verifier.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/asr_process_supervisor.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/high_quality_transcription_service.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/independent_project_rerun_service.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/independent_project_rerun_workflow.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/local_project_transcription_workflow.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/project_proofread_evidence_loader.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/project_rerun_candidate_store.dart';
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
  mode: TranscriptionMode.highestQuality,
  qwenExecutable: 'qwen',
  whisperExecutable: 'whisper',
  modelPath: 'ggml-large-v3.bin',
);

ResolvedTranscriptionProfile _profileFor(TranscriptionConfig config) =>
    ResolvedTranscriptionProfile(
      profile: TranscriptionProfilePreference.custom,
      label: 'test',
      description: 'test',
      hardware: const TranscriptionHardwareInfo(
        operatingSystem: 'linux',
        architecture: 'x86_64',
      ),
      config: config,
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

  group('capture, persistence, and reopen', () {
    test('capture survives workflow save and a fresh repository', () async {
      await h.run();
      final saved = await h.reopen();
      expect(saved.status, ProjectStatus.editing);
      expect(saved.currentStage, ProcessingStage.transcriptionComplete);
      expect(saved.metadata.containsKey('activeTranscriptionRunId'), isFalse);
      expect(saved.lyricDocument!.metadata['editableDraft'], isTrue);
      expect(
        saved.lyricDocument!.metadata['timelineFormat'],
        'lyricforge-timeline-v1',
      );
      final evidence = ChunkedIndependentAsrEvidence.tryParse(
        saved.lyricDocument!.metadata[ChunkedIndependentAsrEvidence
            .metadataKey],
      );
      expect(evidence, isNotNull);
      expect(
        evidence!.sourceAudioSha256,
        sha256.convert(await h.source.readAsBytes()).toString(),
      );
      expect(evidence.chunks, hasLength(2));
      expect(evidence.chunks[0].start, Duration.zero);
      expect(evidence.chunks[0].end, const Duration(seconds: 3));
      expect(evidence.chunks[1].start, const Duration(seconds: 2));
      expect(evidence.chunks[1].end, const Duration(seconds: 4));
      expect(
        saved.lyricDocument!.metadata.containsKey(
          IndependentAsrEvidence.metadataKey,
        ),
        isFalse,
      );
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
      expect(
        result.chunks[1].primary.lines.single.startTime,
        const Duration(seconds: 2),
      );
      expect(
        result.chunks[1].secondary.lines.single.startTime,
        const Duration(milliseconds: 2500),
      );
      expect(
        result.chunks[1].secondary.lines.single.endTime,
        const Duration(milliseconds: 3500),
      );
      expect(result.chunks[0].primaryEngine, 'qwen3-asr-1.7b');
      expect(result.chunks[1].secondaryEngine, 'whisper.cpp-large-v3');
      expect(() => result.chunks.clear(), throwsUnsupportedError);
      expect(jsonEncode((await h.reopen()).toJson()), before);
    });

    test(
      'dual-engine capture preserves chunk overlaps while deduplicating draft',
      () async {
        final hq = await _Harness.createWithHighQuality();
        addTearDown(hq.dispose);
        await hq.run();

        final reopened = await hq.reopen();
        final draft = reopened.lyricDocument!;
        expect(draft.lines.map((line) => line.text).toList(), [
          'opening verse',
          'shared chorus',
          'ending refrain',
          'whisper adlib',
        ]);
        expect(draft.lines[1].confidence, 95);
        expect(
          draft.lines.last.confidenceSource,
          LyricConfidenceSource.heuristic,
        );
        expect(
          draft.metadata.containsKey(IndependentAsrEvidence.metadataKey),
          isFalse,
        );
        expect(hq.ffmpeg.chunkStartRequests, 2);
        expect(hq.ffmpeg.sharedPrepRequests, 2);

        final result = await hq.load(reopened);
        expect(result.status, ProjectProofreadEvidenceStatus.chunkAuditOnly);
        expect(result.primary, isNull);
        expect(result.secondary, isNull);
        expect(result.chunks, hasLength(2));

        // Chunk overlaps must stay un-merged across chunks in global time.
        expect(result.chunks[0].primary.lines.map((l) => l.text).toList(), [
          'opening verse',
          'shared chorus',
        ]);
        expect(result.chunks[0].secondary.lines.map((l) => l.text).toList(), [
          'opening words',
          'shared chorus alt',
        ]);
        expect(result.chunks[1].primary.lines.map((l) => l.text).toList(), [
          'shared chorus',
          'ending refrain',
        ]);
        expect(
          result.chunks[1].primary.lines[0].startTime,
          const Duration(milliseconds: 2100),
        );
        expect(
          result.chunks[1].primary.lines[0].endTime,
          const Duration(milliseconds: 2900),
        );
        expect(result.chunks[1].secondary.lines.map((l) => l.text).toList(), [
          'shared chorus alt',
          'ending words',
          'whisper adlib',
        ]);
        expect(
          result.chunks[1].secondary.lines.last.startTime,
          const Duration(milliseconds: 3750),
        );
      },
    );

    test(
      'whisper-primary engine order captures reversed engines after reopen',
      () async {
        final hq = await _Harness.createWithHighQuality(
          config: _config.copyWith(
            engineOrder: TranscriptionEngineOrder.whisperPrimary,
          ),
        );
        addTearDown(hq.dispose);
        await hq.run();

        final reopened = await hq.reopen();
        final result = await hq.load(reopened);
        expect(result.status, ProjectProofreadEvidenceStatus.chunkAuditOnly);
        expect(result.chunks, hasLength(2));
        expect(result.chunks[0].primaryEngine, 'whisper.cpp-large-v3');
        expect(result.chunks[0].secondaryEngine, 'qwen3-asr-1.7b');
        expect(result.chunks[0].primary.lines.map((l) => l.text).toList(), [
          'opening words',
          'shared chorus alt',
        ]);
        expect(result.chunks[1].secondary.lines.map((l) => l.text).toList(), [
          'shared chorus',
          'ending refrain',
        ]);
      },
    );

    test(
      'degraded second chunk saves draft without exposing partial chunk audit',
      () async {
        final hq = await _Harness.createWithHighQuality(failQwenOnCall: 2);
        addTearDown(hq.dispose);
        await hq.run();

        final reopened = await hq.reopen();
        expect(reopened.status, ProjectStatus.editing);
        expect(reopened.lyricDocument!.lines, isNotEmpty);
        expect(
          reopened.lyricDocument!.metadata.containsKey(
            ChunkedIndependentAsrEvidence.metadataKey,
          ),
          isFalse,
        );
        expect(
          (await hq.load(reopened)).status,
          ProjectProofreadEvidenceStatus.missingEvidence,
        );
      },
    );

    test(
      'whisper-only capture strips forged chunk metadata before save',
      () async {
        final whisper = await _Harness.create(
          config: const TranscriptionConfig(
            mode: TranscriptionMode.whisperOnly,
            whisperExecutable: 'whisper',
            modelPath: 'ggml-large-v3.bin',
          ),
        );
        addTearDown(whisper.dispose);
        await whisper.run();

        final reopened = await whisper.reopen();
        expect(reopened.lyricDocument!.lines, isNotEmpty);
        expect(
          reopened.lyricDocument!.metadata.containsKey(
            ChunkedIndependentAsrEvidence.metadataKey,
          ),
          isFalse,
        );
        expect(
          reopened.lyricDocument!.metadata.containsKey(
            IndependentAsrEvidence.metadataKey,
          ),
          isFalse,
        );
        expect(
          (await whisper.load(reopened)).status,
          ProjectProofreadEvidenceStatus.missingEvidence,
        );
      },
    );

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
      final originalEvidence = old
          .lyricDocument!
          .metadata[ChunkedIndependentAsrEvidence.metadataKey];
      final updated = await h.repo.updateProject(
        old.copyWith(
          lyricDocument: old.lyricDocument!.copyWith(
            lines: _manual.lines,
            metadata: {...old.lyricDocument!.metadata, ..._manual.metadata},
          ),
          currentStage: ProcessingStage.lyricsEdited,
        ),
      );
      final reopened = await h.reopen();
      expect(reopened.revision, updated.revision);
      expect(reopened.lyricDocument!.lines.single.text, 'manual edit');
      expect(
        reopened.lyricDocument!.metadata[ChunkedIndependentAsrEvidence
            .metadataKey],
        originalEvidence,
      );
      final before = jsonEncode(reopened.toJson());
      final result = await h.load(reopened);
      expect(result.status, ProjectProofreadEvidenceStatus.chunkAuditOnly);
      expect(result.chunks[0].primary.lines.single.text, 'primary');
      expect(result.chunks[1].secondary.lines.single.text, 'secondary');
      expect(result.primary, isNull);
      expect(result.secondary, isNull);
      expect(jsonEncode((await h.reopen()).toJson()), before);
    });
  });

  group('cancellation, resume, and coordinator concurrency', () {
    test(
      'concurrent edit during actual chunk capture is not replaced',
      () async {
        final entered = Completer<void>();
        final release = Completer<void>();
        h.onChunk = (request, call) async {
          if (call == 1) {
            entered.complete();
            await release.future;
          }
        };
        final running = h.run();
        final rejected = expectLater(
          running,
          throwsA(
            isA<TranscriptionException>().having(
              (e) => e.message,
              'message',
              contains('未覆盖最新歌词'),
            ),
          ),
        );
        await entered.future;
        final inFlight = await h.current();
        expect(inFlight.status, ProjectStatus.transcribing);
        final latest = await h.repo.updateProject(
          inFlight.copyWith(
            lyricDocument: _manual,
            currentStage: ProcessingStage.lyricsEdited,
            metadata: {...inFlight.metadata, 'concurrent': 'preserved'},
          ),
        );
        release.complete();
        await rejected;
        final reopened = await h.reopen();
        expect(reopened.revision, greaterThan(latest.revision));
        expect(reopened.lyricDocument!.toJson(), _manual.toJson());
        expect(reopened.currentStage, ProcessingStage.lyricsEdited);
        expect(reopened.metadata['concurrent'], 'preserved');
        expect(
          reopened.metadata.containsKey('activeTranscriptionRunId'),
          isFalse,
        );
        expect(
          (await h.load(reopened)).status,
          ProjectProofreadEvidenceStatus.missingEvidence,
        );
      },
    );

    test(
      'cancellation during chunk capture leaves original lyrics on disk',
      () async {
        final entered = Completer<void>();
        final release = Completer<void>();
        h.onChunk = (request, call) async {
          if (call == 1) {
            entered.complete();
            await release.future;
          }
        };
        final running = h.run();
        final rejected = expectLater(
          running,
          throwsA(
            isA<TranscriptionException>().having(
              (e) => e.kind,
              'kind',
              TranscriptionFailureKind.cancelled,
            ),
          ),
        );
        await entered.future;
        final cancel = h.workflow.cancel();
        release.complete();
        await cancel;
        await rejected;
        final reopened = await h.reopen();
        expect(reopened.lyricDocument!.toJson(), _original.toJson());
        expect(reopened.status, ProjectStatus.editing);
        expect(
          reopened.metadata.containsKey('activeTranscriptionRunId'),
          isFalse,
        );
        expect(
          Directory('${h.root.path}/transcription/backups').listSync(),
          hasLength(1),
        );
        expect(
          (await h.load(reopened)).status,
          ProjectProofreadEvidenceStatus.missingEvidence,
        );
      },
    );

    test(
      'cancelling chunk 2 preserves chunk 1 checkpoint and resumes full audit',
      () async {
        final enteredSecond = Completer<void>();
        final releaseSecond = Completer<void>();
        h.onChunk = (request, call) async {
          if (call == 2) {
            enteredSecond.complete();
            await releaseSecond.future;
          }
        };

        final firstRun = h.run();
        final cancelled = expectLater(
          firstRun,
          throwsA(
            isA<TranscriptionException>().having(
              (e) => e.kind,
              'kind',
              TranscriptionFailureKind.cancelled,
            ),
          ),
        );
        await enteredSecond.future;
        final cancelFuture = h.workflow.cancel();
        releaseSecond.complete();
        await cancelFuture;
        await cancelled;

        final mid = await h.reopen();
        expect(mid.status, ProjectStatus.editing);
        expect(mid.lyricDocument!.toJson(), _original.toJson());
        expect(
          File(
            '${h.root.path}/transcription/chunk_session/chunks/chunk_0000.json',
          ).existsSync(),
          isTrue,
        );

        h.onChunk = null;
        await h.run();
        // Chunk 1 came from its checkpoint so chunk 2 ran/extracted once more on resume.
        expect(h.delegate.calls, 3);
        expect(h.ffmpeg.chunkStartRequests, 3);

        final resumed = await h.reopen();
        final loaded = await h.load(resumed);
        expect(loaded.status, ProjectProofreadEvidenceStatus.chunkAuditOnly);
        expect(loaded.chunks, hasLength(2));
        expect(loaded.chunks[0].primary.lines.single.text, 'primary');
        expect(loaded.chunks[1].primary.lines.single.text, 'primary');
      },
    );

    test(
      'resuming after same-size same-mtime source rewrite rejects stale audit',
      () async {
        final enteredSecond = Completer<void>();
        final releaseSecond = Completer<void>();
        h.onChunk = (request, call) async {
          if (call == 2) {
            enteredSecond.complete();
            await releaseSecond.future;
          }
        };
        final firstRun = h.run();
        final cancelled = expectLater(
          firstRun,
          throwsA(
            isA<TranscriptionException>().having(
              (e) => e.kind,
              'kind',
              TranscriptionFailureKind.cancelled,
            ),
          ),
        );
        await enteredSecond.future;
        final cancelFuture = h.workflow.cancel();
        releaseSecond.complete();
        await cancelFuture;
        await cancelled;

        final statBefore = await h.source.stat();
        await h.source.writeAsBytes(List<int>.filled(128, 4));
        await h.source.setLastModified(statBefore.modified);

        h.onChunk = null;
        await h.run();
        final reopened = await h.reopen();
        expect(reopened.lyricDocument!.lines, isNotEmpty);
        expect(
          reopened.lyricDocument!.metadata.containsKey(
            ChunkedIndependentAsrEvidence.metadataKey,
          ),
          isFalse,
        );
        expect(
          (await h.load(reopened)).status,
          ProjectProofreadEvidenceStatus.missingEvidence,
        );
      },
    );

    test(
      'tampered chunk checkpoint evidence digest prevents audit publication',
      () async {
        final enteredSecond = Completer<void>();
        final releaseSecond = Completer<void>();
        h.onChunk = (request, call) async {
          if (call == 2) {
            enteredSecond.complete();
            await releaseSecond.future;
          }
        };
        final firstRun = h.run();
        final cancelled = expectLater(
          firstRun,
          throwsA(
            isA<TranscriptionException>().having(
              (e) => e.kind,
              'kind',
              TranscriptionFailureKind.cancelled,
            ),
          ),
        );
        await enteredSecond.future;
        final cancelFuture = h.workflow.cancel();
        releaseSecond.complete();
        await cancelFuture;
        await cancelled;

        final chunk0 = File(
          '${h.root.path}/transcription/chunk_session/chunks/chunk_0000.json',
        );
        final decoded =
            jsonDecode(await chunk0.readAsString()) as Map<String, dynamic>;
        (decoded['independentEvidence'] as Map)['evidenceSha256'] = '0' * 64;
        await chunk0.writeAsString(jsonEncode(decoded));

        h.onChunk = null;
        await h.run();
        final reopened = await h.reopen();
        expect(reopened.lyricDocument!.lines, isNotEmpty);
        expect(
          (await h.load(reopened)).status,
          ProjectProofreadEvidenceStatus.missingEvidence,
        );
      },
    );

    test(
      'shared resource coordinator blocks rerun/alignment during capture and isolates later rerun',
      () async {
        final entered = Completer<void>();
        final release = Completer<void>();
        h.onChunk = (request, call) async {
          if (call == 1) {
            entered.complete();
            await release.future;
          }
        };
        final rerun = IndependentProjectRerunWorkflow(
          projects: h.repo,
          settings: _Settings(_config),
          profiles: _Resolver(_config),
          runtime: _Runtime(),
          resources: h.resources,
          createWhisper: () => _AsyncService((request, _) async {
            return TranscriptionResult(
              lyrics: const LyricDocument(
                language: 'en',
                lines: [
                  LyricLine(
                    text: 'rerun whisper',
                    startTime: Duration.zero,
                    endTime: Duration(seconds: 2),
                  ),
                ],
              ),
              normalizedAudioPath: request.inputAudioPath,
              rawJsonPath: '${request.outputDirectory}/rerun.json',
              detectedLanguage: 'en',
            );
          }),
        );
        final alignedRunner = coordinateForcedAlignmentRunner(
          resources: h.resources,
          delegate:
              ({
                required audioPath,
                required text,
                required language,
                required audioDuration,
              }) async => const [],
        );

        final running = h.run();
        await entered.future;
        expect(h.resources.activeUse, AsrResourceUse.transcription);

        await expectLater(
          h.workflow.transcribeProject(h.id),
          throwsA(
            isA<TranscriptionException>().having(
              (e) => e.kind,
              'kind',
              TranscriptionFailureKind.busy,
            ),
          ),
        );
        await expectLater(
          rerun.run(projectId: h.id, engine: IndependentRerunEngine.whisper),
          throwsA(
            isA<TranscriptionException>().having(
              (e) => e.kind,
              'kind',
              TranscriptionFailureKind.busy,
            ),
          ),
        );
        await expectLater(
          alignedRunner(
            audioPath: h.source.path,
            text: 'original lyric',
            language: 'en',
            audioDuration: const Duration(seconds: 4),
          ),
          throwsA(isA<ForcedAlignmentResourceBusyException>()),
        );

        release.complete();
        await running;
        expect(h.resources.activeUse, isNull);

        final captured = await h.reopen();
        final savedCandidate = await rerun.run(
          projectId: h.id,
          engine: IndependentRerunEngine.whisper,
        );
        expect(
          savedCandidate.pair.candidate.lines.single.text,
          'rerun whisper',
        );

        // Rerun bumps revision without losing ChunkedIndependentAsrEvidence.
        expect(
          (await h.load(captured)).status,
          ProjectProofreadEvidenceStatus.projectChanged,
        );
        final afterRerun = await h.reopen();
        expect(
          ProjectRerunCandidateStore(h.repo).read(afterRerun),
          hasLength(1),
        );
        final loaded = await h.load(afterRerun);
        expect(loaded.status, ProjectProofreadEvidenceStatus.chunkAuditOnly);
        expect(loaded.chunks, hasLength(2));
      },
    );
  });

  group('audio provenance and corrupt data boundaries', () {
    test(
      'an incomplete independent pair saves a draft but no audit set',
      () async {
        h.includeEvidence = (call) => call == 1;
        await h.run();
        final reopened = await h.reopen();
        expect(reopened.lyricDocument!.lines, isNotEmpty);
        expect(
          reopened.lyricDocument!.metadata.containsKey(
            ChunkedIndependentAsrEvidence.metadataKey,
          ),
          isFalse,
        );
        expect(
          (await h.load(reopened)).status,
          ProjectProofreadEvidenceStatus.missingEvidence,
        );
      },
    );

    test(
      'out-of-bounds chunk timestamps or unknown engine cannot publish audit',
      () async {
        for (final mode in ['badTimes', 'badEngine']) {
          final caseHarness = await _Harness.create();
          addTearDown(caseHarness.dispose);
          caseHarness.delegate = _AsyncService(
            (request, service) => _chunkEvidenceResult(
              request,
              badTimes: mode == 'badTimes',
              badEngine: mode == 'badEngine',
            ),
          );
          caseHarness.chunks = ResumableChunkedTranscriptionService(
            delegate: caseHarness.delegate,
            chunkDuration: const Duration(seconds: 3),
            overlap: const Duration(seconds: 1),
            maxAttempts: 1,
            processSupervisor: caseHarness.ffmpeg.supervisor,
          );
          caseHarness.workflow = caseHarness.buildWorkflow();
          await caseHarness.run();

          final reopened = await caseHarness.reopen();
          expect(reopened.lyricDocument!.lines, isNotEmpty);
          expect(
            (await caseHarness.load(reopened)).status,
            ProjectProofreadEvidenceStatus.missingEvidence,
          );
        }
      },
    );

    test(
      'a changed source during capture cannot publish its audit set',
      () async {
        h.onChunk = (request, call) async {
          if (call == 2) await h.source.writeAsBytes(List<int>.filled(128, 9));
        };
        await h.run();
        final reopened = await h.reopen();
        expect(reopened.lyricDocument!.lines, isNotEmpty);
        expect(
          reopened.lyricDocument!.metadata.containsKey(
            ChunkedIndependentAsrEvidence.metadataKey,
          ),
          isFalse,
        );
        expect(
          (await h.load(reopened)).status,
          ProjectProofreadEvidenceStatus.missingEvidence,
        );
      },
    );

    test(
      'replaced bytes after reopening reject otherwise valid evidence',
      () async {
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
      },
    );

    test('missing audio after reopening is unavailable', () async {
      await h.run();
      final saved = await h.reopen();
      await h.source.delete();
      final result = await h.load(saved);
      expect(result.status, ProjectProofreadEvidenceStatus.audioUnavailable);
      expect(result.chunks, isEmpty);
    });

    test(
      'new preferred vocal stem is verified instead of the old source',
      () async {
        await h.run();
        final old = await h.current();
        final stem = File('${h.root.path}/vocal.wav');
        await stem.writeAsBytes(List<int>.filled(128, 3));
        await h.repo.updateProject(
          old.copyWith(
            audioAsset: old.audioAsset!.copyWith(vocalPath: stem.path),
          ),
        );
        final saved = await h.reopen();
        final result = await h.load(saved);
        expect(result.status, ProjectProofreadEvidenceStatus.audioChanged);
        expect(result.chunks, isEmpty);
      },
    );

    test('revision changed after editor opened rejects old draft', () async {
      await h.run();
      final old = await h.reopen();
      final current = await h.current();
      await h.repo.updateProject(current.copyWith(name: 'new project name'));
      final freshRepo = FileProjectRepository(rootDirectory: h.root);
      final result =
          await VerifiedProjectProofreadEvidenceLoader(
            projects: freshRepo,
          ).load(
            projectId: h.id,
            expectedProjectRevision: old.revision,
            draft: old.lyricDocument!,
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
            rawEvidence: rawEvidence,
            currentAudioPath: currentAudioPath,
          );
          final current = await h.current();
          await h.repo.updateProject(
            current.copyWith(name: 'changed while hashing'),
          );
          return status;
        },
      );
      final result = await loader.load(
        projectId: h.id,
        expectedProjectRevision: saved.revision,
        draft: saved.lyricDocument!,
      );
      expect(result.status, ProjectProofreadEvidenceStatus.projectChanged);
      expect(result.chunks, isEmpty);
      expect((await h.reopen()).name, 'changed while hashing');
    });

    test('unsupported draft offset never exposes captured originals', () async {
      await h.run();
      final saved = await h.reopen();
      final result = await h.load(
        saved,
        draft: saved.lyricDocument!.copyWith(
          globalOffset: const Duration(milliseconds: 50),
        ),
      );
      expect(result.status, ProjectProofreadEvidenceStatus.unsupportedOffsets);
      expect(result.chunks, isEmpty);
    });

    test(
      'simultaneous persisted single and chunk evidence fails closed',
      () async {
        await h.run();
        final saved = await h.current();
        final document = saved.lyricDocument!;
        final chunkEvidence =
            document.metadata[ChunkedIndependentAsrEvidence.metadataKey] as Map;
        final single = (chunkEvidence['chunks'] as List).first['evidence'];
        await h.repo.updateProject(
          saved.copyWith(
            lyricDocument: document.copyWith(
              metadata: {
                ...document.metadata,
                IndependentAsrEvidence.metadataKey: single,
              },
            ),
          ),
        );
        final reopened = await h.reopen();
        final result = await h.load(reopened);
        expect(result.status, ProjectProofreadEvidenceStatus.invalidEvidence);
        expect(result.chunks, isEmpty);
      },
    );

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
      'missing pair': (raw) =>
          (raw['chunks'] as List)[1]['evidence'].remove('secondary'),
      'invalid engine': (raw) =>
          (raw['chunks'] as List)[1]['evidence']['secondary']['engine'] =
              'unknown',
      'empty transcript': (raw) =>
          (raw['chunks'] as List)[0]['evidence']['primary']['lines'] = [],
    };
    for (final entry in corruptions.entries) {
      test('persisted ${entry.key} fails closed after reopening', () async {
        await h.run();
        final saved = await h.current();
        final document = saved.lyricDocument!;
        final raw =
            jsonDecode(
                  jsonEncode(
                    document.metadata[ChunkedIndependentAsrEvidence
                        .metadataKey],
                  ),
                )
                as Map<String, dynamic>;
        entry.value(raw);
        await h.repo.updateProject(
          saved.copyWith(
            lyricDocument: document.copyWith(
              metadata: {
                ...document.metadata,
                ChunkedIndependentAsrEvidence.metadataKey: raw,
              },
            ),
          ),
        );
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
  });
}

const _original = LyricDocument(
  language: 'en',
  lines: [
    LyricLine(
      id: 'original',
      text: 'original lyric',
      startTime: Duration.zero,
      endTime: Duration(seconds: 1),
    ),
  ],
  metadata: {'owner': 'user'},
);

const _manual = LyricDocument(
  language: 'en',
  lines: [
    LyricLine(
      id: 'manual',
      text: 'manual edit',
      startTime: Duration.zero,
      endTime: Duration(seconds: 1),
    ),
  ],
  metadata: {
    'manuallyEditedLineIds': ['manual'],
  },
);

class _Harness {
  _Harness(
    this.root,
    this.source,
    this.repo,
    this.id,
    this.ffmpeg,
    this.config,
    this.resources,
  );

  final Directory root;
  final File source;
  final FileProjectRepository repo;
  final String id;
  final _FfmpegStub ffmpeg;
  final TranscriptionConfig config;
  final AsrResourceCoordinator resources;
  late _AsyncService delegate;
  late ResumableChunkedTranscriptionService chunks;
  late LocalProjectTranscriptionWorkflow workflow;
  Future<void> Function(TranscriptionRequest, int)? onChunk;
  bool Function(int)? includeEvidence;
  File get store => File('${root.path}/projects.json');

  static Future<_Harness> create({TranscriptionConfig config = _config}) async {
    final root = await Directory.systemTemp.createTemp('full-chunk-project-');
    final source = File('${root.path}/source.wav');
    await source.writeAsBytes(List<int>.filled(128, 7));
    final repo = FileProjectRepository(rootDirectory: root);
    final created = await repo.createProject(name: 'song');
    await repo.updateProject(
      created.copyWith(
        projectDirectory: root.path,
        audioAsset: AudioAsset(originalPath: source.path, format: 'wav'),
        lyricDocument: _original,
        status: ProjectStatus.editing,
        currentStage: ProcessingStage.lyricsEdited,
      ),
    );
    final harness = _Harness(
      root,
      source,
      repo,
      created.id,
      _FfmpegStub(durationLabel: '00:00:04.000'),
      config,
      AsrResourceCoordinator(),
    );
    harness.delegate = _AsyncService((request, service) async {
      await harness.onChunk?.call(request, service.calls);
      return _chunkEvidenceResult(
        request,
        includeEvidence: harness.includeEvidence?.call(service.calls) ?? true,
      );
    });
    harness.chunks = ResumableChunkedTranscriptionService(
      delegate: harness.delegate,
      chunkDuration: const Duration(seconds: 3),
      overlap: const Duration(seconds: 1),
      maxAttempts: 1,
      processSupervisor: harness.ffmpeg.supervisor,
    );
    harness.workflow = harness.buildWorkflow();
    return harness;
  }

  static Future<_Harness> createWithHighQuality({
    TranscriptionConfig config = _config,
    int? failQwenOnCall,
  }) async {
    final harness = await create(config: config);
    await harness.chunks.dispose();

    var qwenCalls = 0;
    var whisperCalls = 0;
    final qwen = _AsyncService((request, _) async {
      qwenCalls++;
      if (failQwenOnCall == qwenCalls) {
        throw const TranscriptionException('qwen runtime failure');
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
    final whisper = _AsyncService((request, _) async {
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

    final highQuality = HighQualityTranscriptionService(
      primary: qwen,
      fallback: whisper,
      processSupervisor: harness.ffmpeg.supervisor,
    );
    harness.chunks = ResumableChunkedTranscriptionService(
      delegate: highQuality,
      chunkDuration: const Duration(seconds: 3),
      overlap: const Duration(seconds: 1),
      maxAttempts: 1,
      processSupervisor: harness.ffmpeg.supervisor,
    );
    harness.workflow = harness.buildWorkflow();
    return harness;
  }

  LocalProjectTranscriptionWorkflow buildWorkflow() =>
      LocalProjectTranscriptionWorkflow(
        projectRepository: repo,
        transcriptionService: chunks,
        settingsStore: _Settings(config),
        profileResolver: _Resolver(config),
        runtimeManager: _Runtime(),
        resources: resources,
        mediaMetadataRepository: _UnusedMetadata(),
        playbackSession: _UnusedPlayback(),
        pathCanonicalizer: _UnusedCanonicalizer(),
      );

  Future<void> run() => workflow.transcribeProject(id);
  Future<ProjectManifest> current() async => (await repo.getProjectById(id))!;
  Future<ProjectManifest> reopen() async =>
      (await FileProjectRepository(rootDirectory: root).getProjectById(id))!;
  Future<ProjectProofreadEvidenceResult> load(
    ProjectManifest project, {
    LyricDocument? draft,
  }) =>
      VerifiedProjectProofreadEvidenceLoader(
        projects: FileProjectRepository(rootDirectory: root),
      ).load(
        projectId: id,
        expectedProjectRevision: project.revision,
        draft: draft ?? project.lyricDocument!,
      );
  Future<void> dispose() async {
    await chunks.dispose();
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  }
}

class _FfmpegStub {
  _FfmpegStub({required this.durationLabel});

  final String durationLabel;
  int chunkStartRequests = 0;
  int sharedPrepRequests = 0;

  AsrProcessSupervisor get supervisor => AsrProcessSupervisor(
    startProcess: (_, arguments) async {
      final process = _FakeProcess();
      if (arguments.contains('-vn')) {
        if (arguments.contains('-ss')) {
          chunkStartRequests++;
          await File(
            arguments.last,
          ).writeAsBytes(List<int>.filled(128, chunkStartRequests));
        } else {
          sharedPrepRequests++;
          await File(
            arguments.last,
          ).writeAsBytes(List<int>.filled(128, sharedPrepRequests + 32));
        }
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

Future<TranscriptionResult> _chunkEvidenceResult(
  TranscriptionRequest request, {
  bool includeEvidence = true,
  bool badTimes = false,
  bool badEngine = false,
}) async {
  final hash = sha256
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
  _Settings(this.config);
  final TranscriptionConfig config;
  @override
  Future<TranscriptionConfig?> load() async => config;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Resolver implements TranscriptionProfileResolver {
  _Resolver(this.config);
  final TranscriptionConfig config;
  @override
  Future<ResolvedTranscriptionProfile> resolve(
    TranscriptionConfig requested,
  ) async => _profileFor(config);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Runtime implements AsrRuntimeManager {
  @override
  bool get isInstalling => false;
  @override
  Future<TranscriptionConfig> repair(TranscriptionConfig config) async =>
      config;
  @override
  Future<AsrRuntimeStatus> inspect(TranscriptionConfig config) async =>
      AsrRuntimeStatus(
        profile: _profileFor(config),
        components: const [
          AsrRuntimeComponentStatus(
            component: AsrRuntimeComponent.ffmpeg,
            state: AsrRuntimeComponentState.ready,
            label: 'FFmpeg',
            detail: 'ready',
          ),
          AsrRuntimeComponentStatus(
            component: AsrRuntimeComponent.whisperRuntime,
            state: AsrRuntimeComponentState.ready,
            label: 'Whisper Runtime',
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
            label: 'Qwen Runtime',
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

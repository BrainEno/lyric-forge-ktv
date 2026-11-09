import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/project/data/repositories/file_project_repository.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/asr_evidence_audio_verifier.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/independent_project_rerun_service.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/project_rerun_candidate_assessor.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/project_rerun_candidate_store.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';

const original = LyricDocument(
  language: 'en',
  lines: [
    LyricLine(
      id: '1',
      text: 'human',
      startTime: Duration.zero,
      endTime: Duration(seconds: 2),
    ),
  ],
  metadata: {
    'manual': ['1'],
  },
);
const candidate = LyricDocument(
  language: 'en',
  lines: [
    LyricLine(
      text: 'asr',
      startTime: Duration.zero,
      endTime: Duration(seconds: 2),
    ),
  ],
);

void main() {
  late Directory root;
  late File audio;
  late File vocal;
  late FileProjectRepository repo;
  late ProjectManifest project;
  late SavedRerunCandidate saved;
  late ProjectRerunCandidateAssessor assessor;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('candidate-assessment-');
    audio = File('${root.path}/original.wav');
    vocal = File('${root.path}/vocal.wav');
    await audio.writeAsBytes([1, 2, 3]);
    repo = FileProjectRepository(rootDirectory: root);
    final created = await repo.createProject(name: 'Song');
    project = await repo.updateProject(
      created.copyWith(
        audioAsset: AudioAsset(
          originalPath: audio.path,
          vocalPath: vocal.path,
          format: 'wav',
        ),
        lyricDocument: original,
      ),
    );
    saved = await ProjectRerunCandidateStore(repo).save(
      IndependentRerunCandidate(
        projectId: project.id,
        projectRevision: project.revision,
        engine: IndependentRerunEngine.whisper,
        inputAudioPath: audio.path,
        inputAudioSha256: sha256.convert([1, 2, 3]).toString(),
        modelReference: 'model',
        alignerReference: null,
        requestedLanguage: 'auto',
        detectedLanguage: 'en',
        original: original,
        candidate: candidate,
      ),
    );
    assessor = ProjectRerunCandidateAssessor(projects: repo);
  });
  tearDown(() async => root.delete(recursive: true));

  Future<RerunCandidateAssessment> assess() =>
      assessor.assess(projectId: project.id, candidateId: saved.id);

  test(
    'reopened store reports matching baseline and selected bytes without writes',
    () async {
      final reopened = FileProjectRepository(rootDirectory: root);
      final result = await ProjectRerunCandidateAssessor(
        projects: reopened,
      ).assess(projectId: project.id, candidateId: saved.id);
      expect(result.saved.pair.candidate.toJson(), candidate.toJson());
      expect(result.observedProjectRevision, project.revision + 1);
      expect(result.baselineMatches, isTrue);
      expect(result.audioStatus, RerunCandidateAudioStatus.matches);
      expect(result.modelStatus, RerunCandidateModelStatus.unverified);
      expect(
        (await reopened.getProjectById(project.id))!.lyricDocument!.toJson(),
        original.toJson(),
      );
    },
  );

  test(
    'baseline and audio status are independent and include manual metadata',
    () async {
      final current = (await repo.getProjectById(project.id))!;
      await repo.updateProject(
        current.copyWith(
          lyricDocument: original.copyWith(metadata: {'manual': []}),
        ),
      );
      var report = await assess();
      expect(report.baselineMatches, isFalse);
      expect(report.audioStatus, RerunCandidateAudioStatus.matches);
      await audio.writeAsBytes([3, 2, 1]);
      report = await assess();
      expect(report.baselineMatches, isFalse);
      expect(report.audioStatus, RerunCandidateAudioStatus.changed);
    },
  );

  test(
    'detects changed selected stem even when its bytes are identical',
    () async {
      await vocal.writeAsBytes([1, 2, 3]);
      expect(
        (await assess()).audioStatus,
        RerunCandidateAudioStatus.selectionChanged,
      );
    },
  );

  test('missing and unreadable audio are not matches', () async {
    await audio.delete();
    expect((await assess()).audioStatus, RerunCandidateAudioStatus.unavailable);
    await audio.writeAsBytes([1, 2, 3]);
    assessor = ProjectRerunCandidateAssessor(
      projects: repo,
      hashAudio: (_) async => throw const FileSystemException('unreadable'),
    );
    expect((await assess()).audioStatus, RerunCandidateAudioStatus.unavailable);
  });

  test(
    'file changing during read and newly selected stem are not matches',
    () async {
      assessor = ProjectRerunCandidateAssessor(
        projects: repo,
        hashAudio: (_) async =>
            throw const AsrAudioChangedDuringHashException(),
      );
      expect((await assess()).audioStatus, RerunCandidateAudioStatus.changed);
      assessor = ProjectRerunCandidateAssessor(
        projects: repo,
        hashAudio: (_) async {
          await vocal.writeAsBytes([1, 2, 3]);
          return saved.pair.inputAudioSha256;
        },
      );
      expect(
        (await assess()).audioStatus,
        RerunCandidateAudioStatus.selectionChanged,
      );
    },
  );

  test(
    'revision-only changes do not mark an identical lyric baseline changed',
    () async {
      final current = (await repo.getProjectById(project.id))!;
      await repo.updateProject(current.copyWith(name: 'new title'));
      final result = await assess();
      expect(result.observedProjectRevision, current.revision + 1);
      expect(result.baselineMatches, isTrue);
      expect(result.modelStatus, RerunCandidateModelStatus.unverified);
    },
  );

  test('project deleted while hashing rejects the entire report', () async {
    assessor = ProjectRerunCandidateAssessor(
      projects: repo,
      hashAudio: (_) async {
        await repo.deleteProject(project.id);
        return saved.pair.inputAudioSha256;
      },
    );
    await expectLater(assess(), throwsA(isA<TranscriptionException>()));
  });

  test('project edited during hashing rejects the entire report', () async {
    assessor = ProjectRerunCandidateAssessor(
      projects: repo,
      hashAudio: (_) async {
        final latest = (await repo.getProjectById(project.id))!;
        await repo.updateProject(latest.copyWith(lyricDocument: candidate));
        return saved.pair.inputAudioSha256;
      },
    );
    await expectLater(
      assess(),
      throwsA(
        isA<TranscriptionException>().having(
          (e) => e.kind,
          'kind',
          TranscriptionFailureKind.input,
        ),
      ),
    );
    expect(
      (await repo.getProjectById(project.id))!.lyricDocument!.toJson(),
      candidate.toJson(),
    );
  });

  test(
    'missing projects or records and corrupt metadata fail closed',
    () async {
      await expectLater(
        assessor.assess(projectId: project.id, candidateId: 'missing'),
        throwsA(isA<TranscriptionException>()),
      );
      await expectLater(
        assessor.assess(projectId: 'missing', candidateId: saved.id),
        throwsA(isA<TranscriptionException>()),
      );
      final current = (await repo.getProjectById(project.id))!;
      await repo.updateProject(
        current.copyWith(
          metadata: {
            ProjectRerunCandidateStore.metadataKey: {
              'schemaVersion': 2,
              'items': [],
            },
          },
        ),
      );
      await expectLater(assess(), throwsFormatException);
    },
  );
}

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/project_proofread_evidence.dart';
import 'package:lyric_forge_ktv/features/project/data/repositories/file_project_repository.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/asr_evidence_audio_verifier.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/project_proofread_evidence_loader.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/chunked_independent_asr_evidence.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/independent_asr_evidence.dart';

import 'chunk_audit_fixtures.dart';

const draft = LyricDocument(
  language: 'en',
  lines: [
    LyricLine(
      id: 'protected',
      text: 'my edited lyric',
      startTime: Duration.zero,
      endTime: Duration(seconds: 1),
    ),
  ],
);

void main() {
  late Directory root;
  late File source;
  late File stem;
  late FileProjectRepository repo;
  late String projectId;
  late int revision;
  late VerifiedProjectProofreadEvidenceLoader loader;
  final sourceBytes = [1, 2, 3];
  final hash = sha256.convert(sourceBytes).toString();

  Future<void> save(Map<String, dynamic> metadata) async {
    final old = (await repo.getProjectById(projectId))!;
    final updated = await repo.updateProject(
      old.copyWith(lyricDocument: draft.copyWith(metadata: metadata)),
    );
    revision = updated.revision;
  }

  Future<void> saveChunks(Object? value) =>
      save({ChunkedIndependentAsrEvidence.metadataKey: value});

  Future<ProjectProofreadEvidenceResult> load({
    LyricDocument current = draft,
    int? expected,
  }) => loader.load(
    projectId: projectId,
    expectedProjectRevision: expected ?? revision,
    draft: current,
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('chunk-audit-loader-');
    source = File('${root.path}/source.wav');
    stem = File('${root.path}/stem.wav');
    await source.writeAsBytes(sourceBytes);
    repo = FileProjectRepository(rootDirectory: root);
    final created = await repo.createProject(name: 'song');
    projectId = created.id;
    final updated = await repo.updateProject(
      created.copyWith(
        audioAsset: AudioAsset(
          originalPath: source.path,
          vocalPath: stem.path,
          format: 'wav',
        ),
        lyricDocument: draft,
      ),
    );
    revision = updated.revision;
    loader = VerifiedProjectProofreadEvidenceLoader(projects: repo);
    await saveChunks(chunkAuditFixture(hash));
  });
  tearDown(() async => root.delete(recursive: true));

  test(
    'verified complete plan exposes read-only originals in absolute time',
    () async {
      final before = (await repo.getProjectById(projectId))!.toJson();
      final result = await load();
      expect(result.status, ProjectProofreadEvidenceStatus.chunkAuditOnly);
      expect(result.primary, isNull);
      expect(result.secondary, isNull);
      expect(result.chunks, hasLength(2));
      expect(result.chunks[0].index, 0);
      expect(result.chunks[0].start, Duration.zero);
      expect(result.chunks[0].end, const Duration(seconds: 3));
      expect(result.chunks[1].start, const Duration(seconds: 2));
      expect(result.chunks[1].end, const Duration(seconds: 4));
      expect(
        result.chunks[1].primary.lines.single.startTime,
        const Duration(milliseconds: 2500),
      );
      expect(
        result.chunks[1].primary.lines.single.endTime,
        const Duration(milliseconds: 3500),
      );
      expect(
        result.chunks[1].secondary.lines.single.startTime,
        const Duration(milliseconds: 2750),
      );
      expect(
        result.chunks[1].secondary.lines.single.endTime,
        const Duration(milliseconds: 3750),
      );
      expect(result.chunks[1].primary.lines.single.text, 'second primary');
      expect(result.chunks[1].secondary.lines.single.text, 'second secondary');
      expect(result.chunks[1].capturedAtUtc, DateTime.utc(2026, 11, 7));
      expect(result.chunks[1].primaryEngine, 'qwen3-asr-1.7b');
      expect(result.chunks[1].secondaryEngine, 'whisper.cpp-large-v3');
      expect((await repo.getProjectById(projectId))!.toJson(), before);
      expect(() => result.chunks.clear(), throwsUnsupportedError);
      expect(
        () => result.chunks.first.primary.lines.clear(),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'edited, reordered or matching drafts cannot become chunk consensus',
    () async {
      for (final current in [
        draft,
        draft.copyWith(lines: []),
        draft.copyWith(
          lines: [draft.lines.single.copyWith(text: 'first primary')],
        ),
        draft.copyWith(language: 'zh'),
        draft.copyWith(
          lines: [draft.lines.single.copyWith(text: 'manual edit')],
        ),
      ]) {
        final result = await load(current: current);
        expect(result.status, ProjectProofreadEvidenceStatus.chunkAuditOnly);
        expect(result.secondary, isNull);
        expect(result.primary, isNull);
        expect(result.chunks, hasLength(2));
      }
    },
  );

  test(
    'different selected stem blocks reuse even when original matches',
    () async {
      await stem.writeAsBytes([5, 6, 7]);
      final result = await load();
      expect(result.status, ProjectProofreadEvidenceStatus.audioChanged);
      expect(result.chunks, isEmpty);
      expect(result.secondary, isNull);
    },
  );

  test('selected stem with matching bytes is verified', () async {
    await stem.writeAsBytes(sourceBytes);
    expect(
      (await load()).status,
      ProjectProofreadEvidenceStatus.chunkAuditOnly,
    );
  });

  test('unreadable or changed source rejects the complete pair', () async {
    await source.writeAsBytes([3, 2, 1]);
    final changed = await load();
    expect(changed.status, ProjectProofreadEvidenceStatus.audioChanged);
    expect(changed.chunks, isEmpty);
    await source.delete();
    final missing = await load();
    expect(missing.status, ProjectProofreadEvidenceStatus.audioUnavailable);
    expect(missing.chunks, isEmpty);
  });

  test('changed bytes with the same size and timestamp are rejected', () async {
    final modified = (await source.stat()).modified;
    await source.writeAsBytes([3, 2, 1]);
    await source.setLastModified(modified);
    expect((await load()).status, ProjectProofreadEvidenceStatus.audioChanged);
  });

  test('a stale revision is rejected before hashing', () async {
    var calls = 0;
    loader = VerifiedProjectProofreadEvidenceLoader(
      projects: repo,
      verifyAudio: ({required rawEvidence, required currentAudioPath}) async {
        calls++;
        return AsrEvidenceAudioStatus.audioMatches;
      },
    );
    final result = await load(expected: revision - 1);
    expect(result.status, ProjectProofreadEvidenceStatus.projectChanged);
    expect(result.chunks, isEmpty);
    expect(calls, 0);
  });

  test('project update during async hash discards the whole audit', () async {
    loader = VerifiedProjectProofreadEvidenceLoader(
      projects: repo,
      verifyAudio: ({required rawEvidence, required currentAudioPath}) async {
        final old = (await repo.getProjectById(projectId))!;
        await repo.updateProject(old.copyWith(name: 'concurrent change'));
        return AsrEvidenceAudioStatus.audioMatches;
      },
    );
    final result = await load();
    expect(result.status, ProjectProofreadEvidenceStatus.projectChanged);
    expect(result.chunks, isEmpty);
  });

  test('new selected input during async hash discards the audit', () async {
    loader = VerifiedProjectProofreadEvidenceLoader(
      projects: repo,
      verifyAudio: ({required rawEvidence, required currentAudioPath}) async {
        await stem.writeAsBytes(sourceBytes);
        return AsrEvidenceAudioStatus.audioMatches;
      },
    );
    final result = await load();
    expect(result.status, ProjectProofreadEvidenceStatus.audioSelectionChanged);
    expect(result.chunks, isEmpty);
  });

  test('each verifier failure is propagated with no transcripts', () async {
    final outcomes = {
      AsrEvidenceAudioStatus.missingEvidence:
          ProjectProofreadEvidenceStatus.missingEvidence,
      AsrEvidenceAudioStatus.invalidEvidence:
          ProjectProofreadEvidenceStatus.invalidEvidence,
      AsrEvidenceAudioStatus.unverified:
          ProjectProofreadEvidenceStatus.unverifiedAudio,
      AsrEvidenceAudioStatus.audioUnavailable:
          ProjectProofreadEvidenceStatus.audioUnavailable,
      AsrEvidenceAudioStatus.audioChanged:
          ProjectProofreadEvidenceStatus.audioChanged,
    };
    for (final entry in outcomes.entries) {
      loader = VerifiedProjectProofreadEvidenceLoader(
        projects: repo,
        verifyAudio:
            ({required rawEvidence, required currentAudioPath}) async =>
                entry.key,
      );
      final result = await load();
      expect(result.status, entry.value);
      expect(result.chunks, isEmpty);
      expect(result.primary, isNull);
      expect(result.secondary, isNull);
    }
  });

  test(
    'nonzero draft offset fails closed instead of shifting snapshots',
    () async {
      final result = await load(
        current: draft.copyWith(globalOffset: const Duration(seconds: 1)),
      );
      expect(result.status, ProjectProofreadEvidenceStatus.unsupportedOffsets);
      expect(result.chunks, isEmpty);
    },
  );

  test('missing single and chunk evidence reports unavailable', () async {
    await save({});
    final result = await load();
    expect(result.status, ProjectProofreadEvidenceStatus.missingEvidence);
    expect(result.chunks, isEmpty);
  });

  test('simultaneous single and chunk evidence fails closed', () async {
    final chunk = chunkAuditFixture(hash);
    final single = (chunk['chunks'] as List).first['evidence'];
    await save({
      IndependentAsrEvidence.metadataKey: single,
      ChunkedIndependentAsrEvidence.metadataKey: chunk,
    });
    final result = await load();
    expect(result.status, ProjectProofreadEvidenceStatus.invalidEvidence);
    expect(result.chunks, isEmpty);
    expect(result.secondary, isNull);
  });

  test(
    'incomplete, malformed or mismatched plans never expose partial chunks',
    () async {
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (r) => (r['chunks'] as List).removeLast(),
        (r) => (r['chunks'] as List)[1]['startMs'] = 2001,
        (r) => (r['chunks'] as List)[1]['endMs'] = 3999,
        (r) => (r['chunks'] as List)[1]['index'] = 0,
        (r) =>
            (r['chunks']
                    as List)[0]['evidence']['primary']['lines'][0]['endTime'] =
                3001,
        (r) => (r['chunks'] as List)[0]['evidence']['sourceAudioSha256'] = null,
        (r) => (r['chunks'] as List)[1]['evidence']['secondary']['engine'] =
            'unknown',
        (r) => r['sourceAudioSha256'] = 'invalid',
        (r) => r['scope'] = 'singleInput',
        (r) => r['schemaVersion'] = 7,
      ]) {
        final raw =
            jsonDecode(jsonEncode(chunkAuditFixture(hash)))
                as Map<String, dynamic>;
        mutate(raw);
        await saveChunks(raw);
        final result = await load();
        expect(result.status, ProjectProofreadEvidenceStatus.invalidEvidence);
        expect(result.chunks, isEmpty);
        expect(result.secondary, isNull);
      }
    },
  );
}

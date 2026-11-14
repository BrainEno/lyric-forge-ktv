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
import 'package:lyric_forge_ktv/features/transcription/data/services/whisper_json_artifact_reader.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/independent_asr_evidence.dart';

const primary = LyricDocument(
  language: 'en',
  lines: [
    LyricLine(
      id: 'a',
      text: 'first line',
      startTime: Duration.zero,
      endTime: Duration(seconds: 2),
      confidence: 90,
      confidenceSource: LyricConfidenceSource.model,
    ),
    LyricLine(
      id: 'b',
      text: 'second line',
      startTime: Duration(seconds: 2),
      endTime: Duration(seconds: 4),
    ),
  ],
);
const secondary = LyricDocument(
  language: 'en',
  lines: [
    LyricLine(
      text: 'another line',
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
  late String id;
  late int revision;
  late VerifiedProjectProofreadEvidenceLoader loader;
  final hash = sha256.convert([1, 2, 3]).toString();

  Map<String, dynamic> evidence({
    String? sourceHash,
    LyricDocument primaryDoc = primary,
    LyricDocument secondaryDoc = secondary,
    String first = 'qwen3-asr-1.7b',
    String second = 'whisper.cpp-large-v3',
  }) => IndependentAsrEvidence(
    capturedAt: DateTime.utc(2026, 11, 7),
    sourceAudioSha256: sourceHash,
    primary: IndependentAsrTranscript(engine: first, document: primaryDoc),
    secondary: IndependentAsrTranscript(engine: second, document: secondaryDoc),
  ).toJson();

  Future<void> save(
    Object? raw, {
    LyricDocument doc = primary,
    Map<String, dynamic> extraMetadata = const {},
  }) async {
    final project = (await repo.getProjectById(id))!;
    final updated = await repo.updateProject(
      project.copyWith(
        lyricDocument: doc.copyWith(
          metadata: {
            ...extraMetadata,
            if (raw != null) IndependentAsrEvidence.metadataKey: raw,
          },
        ),
      ),
    );
    revision = updated.revision;
  }

  Future<ProjectProofreadEvidenceResult> load({
    LyricDocument doc = primary,
    int? expected,
  }) => loader.load(
    projectId: id,
    expectedProjectRevision: expected ?? revision,
    draft: doc,
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('proofread-evidence-');
    audio = File('${root.path}/original.wav');
    vocal = File('${root.path}/vocal.wav');
    await audio.writeAsBytes([1, 2, 3]);
    repo = FileProjectRepository(rootDirectory: root);
    final created = await repo.createProject(name: 'Song');
    id = created.id;
    final updated = await repo.updateProject(
      created.copyWith(
        audioAsset: AudioAsset(
          originalPath: audio.path,
          vocalPath: vocal.path,
          format: 'wav',
        ),
        lyricDocument: primary,
      ),
    );
    revision = updated.revision;
    loader = VerifiedProjectProofreadEvidenceLoader(projects: repo);
    await save(evidence(sourceHash: hash));
  });
  tearDown(() async => root.delete(recursive: true));

  test(
    'matching primary and bytes expose only an ephemeral second transcript',
    () async {
      final before = (await repo.getProjectById(id))!.toJson();
      final result = await load();
      expect(result.status, ProjectProofreadEvidenceStatus.available);
      expect(result.secondary!.toJson(), secondary.toJson());
      expect(result.secondaryEngine, 'whisper.cpp-large-v3');
      expect(result.capturedAtUtc, DateTime.utc(2026, 11, 7));
      expect((await repo.getProjectById(id))!.toJson(), before);
    },
  );

  test('either engine can be primary', () async {
    await save(
      evidence(
        sourceHash: hash,
        first: 'whisper.cpp-large-v3',
        second: 'qwen3-asr-1.7b',
      ),
    );
    expect((await load()).secondaryEngine, 'qwen3-asr-1.7b');
  });

  test(
    'absent, malformed, duplicate and unknown engines are rejected',
    () async {
      await save(null);
      expect(
        (await load()).status,
        ProjectProofreadEvidenceStatus.missingEvidence,
      );
      await save({'schemaVersion': 5});
      expect(
        (await load()).status,
        ProjectProofreadEvidenceStatus.invalidEvidence,
      );
      for (final engine in [
        'qwen3-asr-1.7b',
        'other-engine',
        'whisper.cpp-/private/path',
      ]) {
        await save(evidence(sourceHash: hash, second: engine));
        expect(
          (await load()).status,
          ProjectProofreadEvidenceStatus.invalidEvidence,
        );
      }
    },
  );

  test(
    'old snapshot, changed bytes and missing files are not matches',
    () async {
      await save(evidence());
      expect(
        (await load()).status,
        ProjectProofreadEvidenceStatus.unverifiedAudio,
      );
      await save(evidence(sourceHash: hash));
      await audio.writeAsBytes([3, 2, 1]);
      expect(
        (await load()).status,
        ProjectProofreadEvidenceStatus.audioChanged,
      );
      await audio.delete();
      expect(
        (await load()).status,
        ProjectProofreadEvidenceStatus.audioUnavailable,
      );
    },
  );

  test(
    'uses the actual selected stem, even when another file matches',
    () async {
      await vocal.writeAsBytes([4, 5, 6]);
      expect(
        (await load()).status,
        ProjectProofreadEvidenceStatus.audioChanged,
      );
      await vocal.writeAsBytes([1, 2, 3]);
      expect((await load()).status, ProjectProofreadEvidenceStatus.available);
    },
  );

  test(
    'changed draft only exposes originals for read-only inspection',
    () async {
      final first = primary.lines.first;
      final variants = [
        primary.copyWith(
          lines: [
            first.copyWith(text: 'edited'),
            primary.lines.last,
          ],
        ),
        primary.copyWith(
          lines: [
            first.copyWith(startTime: const Duration(milliseconds: 1)),
            primary.lines.last,
          ],
        ),
        primary.copyWith(
          lines: [
            first.copyWith(endTime: const Duration(milliseconds: 1999)),
            primary.lines.last,
          ],
        ),
        primary.copyWith(
          lines: [first.copyWith(confidence: 88), primary.lines.last],
        ),
        primary.copyWith(
          lines: [
            first.copyWith(confidenceSource: LyricConfidenceSource.heuristic),
            primary.lines.last,
          ],
        ),
        primary.copyWith(lines: primary.lines.reversed.toList()),
        primary.copyWith(lines: [first]),
        primary.copyWith(language: 'zh'),
      ];
      for (final doc in variants) {
        expect(
          (await load(doc: doc)).status,
          ProjectProofreadEvidenceStatus.auditOnly,
        );
      }
    },
  );

  test(
    'ids and chorus labels do not affect independent text and timing',
    () async {
      final doc = primary.copyWith(
        lines: [
          primary.lines.first.copyWith(id: 'new', isChorus: true),
          primary.lines.last,
        ],
      );
      expect(
        (await load(doc: doc)).status,
        ProjectProofreadEvidenceStatus.available,
      );
    },
  );

  test('nonzero offsets and invalid temporal ordering fail closed', () async {
    expect(
      (await load(
        doc: primary.copyWith(globalOffset: const Duration(milliseconds: 1)),
      )).status,
      ProjectProofreadEvidenceStatus.unsupportedOffsets,
    );
    await save(
      evidence(
        sourceHash: hash,
        secondaryDoc: secondary.copyWith(
          globalOffset: const Duration(seconds: 1),
        ),
      ),
    );
    expect(
      (await load()).status,
      ProjectProofreadEvidenceStatus.unsupportedOffsets,
    );
    final unordered = primary.copyWith(lines: primary.lines.reversed.toList());
    await save(evidence(sourceHash: hash, secondaryDoc: unordered));
    expect(
      (await load()).status,
      ProjectProofreadEvidenceStatus.invalidEvidence,
    );
    await save(
      evidence(
        sourceHash: hash,
        secondaryDoc: secondary.copyWith(
          lines: [secondary.lines.first.copyWith(text: '  ')],
        ),
      ),
    );
    expect(
      (await load()).status,
      ProjectProofreadEvidenceStatus.invalidEvidence,
    );
  });

  test('stale project revision rejected before and after hashing', () async {
    expect(
      (await load(expected: revision - 1)).status,
      ProjectProofreadEvidenceStatus.projectChanged,
    );
    loader = VerifiedProjectProofreadEvidenceLoader(
      projects: repo,
      verifyAudio: ({required rawEvidence, required currentAudioPath}) async {
        final project = (await repo.getProjectById(id))!;
        await repo.updateProject(project.copyWith(name: 'changed'));
        return AsrEvidenceAudioStatus.audioMatches;
      },
    );
    expect(
      (await load()).status,
      ProjectProofreadEvidenceStatus.projectChanged,
    );
  });

  test('detects selected input changing during hash', () async {
    loader = VerifiedProjectProofreadEvidenceLoader(
      projects: repo,
      verifyAudio: ({required rawEvidence, required currentAudioPath}) async {
        await vocal.writeAsBytes([1, 2, 3]);
        return AsrEvidenceAudioStatus.audioMatches;
      },
    );
    expect(
      (await load()).status,
      ProjectProofreadEvidenceStatus.audioSelectionChanged,
    );
  });

  test(
    'propagates each verifier outcome without exposing a transcript',
    () async {
      final cases = {
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
      for (final entry in cases.entries) {
        loader = VerifiedProjectProofreadEvidenceLoader(
          projects: repo,
          verifyAudio:
              ({required rawEvidence, required currentAudioPath}) async =>
                  entry.key,
        );
        final result = await load();
        expect(result.status, entry.value);
        expect(result.secondary, isNull);
      }
    },
  );

  group('read-only original snapshot audit', () {
    final changed = primary.copyWith(
      lines: [
        primary.lines.first.copyWith(text: 'fused or manually edited'),
        primary.lines.last,
      ],
    );

    test(
      'returns both originals, not the changed draft, with provenance',
      () async {
        final before = (await repo.getProjectById(id))!.toJson();
        final result = await load(doc: changed);
        expect(result.status, ProjectProofreadEvidenceStatus.auditOnly);
        expect(result.primary!.toJson(), primary.toJson());
        expect(result.secondary!.toJson(), secondary.toJson());
        expect(result.primaryEngine, 'qwen3-asr-1.7b');
        expect(result.secondaryEngine, 'whisper.cpp-large-v3');
        expect(result.capturedAtUtc, DateTime.utc(2026, 11, 7));
        expect(
          result.primary!.lines.first.text,
          isNot(changed.lines.first.text),
        );
        expect((await repo.getProjectById(id))!.toJson(), before);
      },
    );

    test('unverified source never exposes original transcript pair', () async {
      await save(evidence());
      final result = await load(doc: changed);
      expect(result.status, ProjectProofreadEvidenceStatus.unverifiedAudio);
      expect(result.primary, isNull);
      expect(result.secondary, isNull);
    });

    test('changed source never exposes original transcript pair', () async {
      await audio.writeAsBytes([4, 5, 6]);
      final result = await load(doc: changed);
      expect(result.status, ProjectProofreadEvidenceStatus.audioChanged);
      expect(result.primary, isNull);
      expect(result.secondary, isNull);
    });

    test(
      'missing selected input never exposes original transcript pair',
      () async {
        await audio.delete();
        final result = await load(doc: changed);
        expect(result.status, ProjectProofreadEvidenceStatus.audioUnavailable);
        expect(result.primary, isNull);
        expect(result.secondary, isNull);
      },
    );

    test(
      'different selected stem cannot reuse matching original file',
      () async {
        await vocal.writeAsBytes([8, 9]);
        final result = await load(doc: changed);
        expect(result.status, ProjectProofreadEvidenceStatus.audioChanged);
        expect(result.primary, isNull);
        expect(result.secondary, isNull);
      },
    );

    test('changing selected stem during verification rejects audit', () async {
      loader = VerifiedProjectProofreadEvidenceLoader(
        projects: repo,
        verifyAudio: ({required rawEvidence, required currentAudioPath}) async {
          await vocal.writeAsBytes([1, 2, 3]);
          return AsrEvidenceAudioStatus.audioMatches;
        },
      );
      final result = await load(doc: changed);
      expect(
        result.status,
        ProjectProofreadEvidenceStatus.audioSelectionChanged,
      );
      expect(result.primary, isNull);
      expect(result.secondary, isNull);
    });

    test(
      'project revision changing during verification rejects audit',
      () async {
        loader = VerifiedProjectProofreadEvidenceLoader(
          projects: repo,
          verifyAudio:
              ({required rawEvidence, required currentAudioPath}) async {
                final current = (await repo.getProjectById(id))!;
                await repo.updateProject(
                  current.copyWith(name: 'Changed concurrently'),
                );
                return AsrEvidenceAudioStatus.audioMatches;
              },
        );
        final result = await load(doc: changed);
        expect(result.status, ProjectProofreadEvidenceStatus.projectChanged);
        expect(result.primary, isNull);
        expect(result.secondary, isNull);
      },
    );

    test('unsupported draft or source offset is not converted', () async {
      final shifted = changed.copyWith(
        globalOffset: const Duration(seconds: 1),
      );
      final result = await load(doc: shifted);
      expect(result.status, ProjectProofreadEvidenceStatus.unsupportedOffsets);
      expect(result.primary, isNull);
      expect(result.secondary, isNull);
    });

    test(
      'malformed or chunk scoped metadata cannot supply originals',
      () async {
        for (final scope in ['chunk', 'multiInput', 'unknown']) {
          final raw = evidence(sourceHash: hash)..['scope'] = scope;
          await save(raw);
          final result = await load(doc: changed);
          expect(result.status, ProjectProofreadEvidenceStatus.invalidEvidence);
          expect(result.primary, isNull);
          expect(result.secondary, isNull);
        }
      },
    );

    test('unknown engine identity cannot supply originals', () async {
      await save(evidence(sourceHash: hash, second: 'unknown'));
      final result = await load(doc: changed);
      expect(result.status, ProjectProofreadEvidenceStatus.invalidEvidence);
      expect(result.primary, isNull);
      expect(result.secondary, isNull);
    });

    test('same engine identities cannot supply originals', () async {
      await save(evidence(sourceHash: hash, second: 'qwen3-asr-1.7b'));
      final result = await load(doc: changed);
      expect(result.status, ProjectProofreadEvidenceStatus.invalidEvidence);
      expect(result.primary, isNull);
      expect(result.secondary, isNull);
    });
  });

  group('metadata-only evidence preview', () {
    test('matching source draft is a default-selection candidate', () async {
      final hint = await loader.preview(
        projectId: id,
        expectedProjectRevision: revision,
        draft: primary,
      );
      expect(
        hint.status,
        ProjectProofreadEvidenceHintStatus.currentDraftCandidate,
      );
      expect(hint.shouldOffer, isTrue);
      expect(hint.shouldSelectByDefault, isTrue);
      expect(hint.primaryEngine, 'qwen3-asr-1.7b');
      expect(hint.secondaryEngine, 'whisper.cpp-large-v3');
      expect(hint.capturedAtUtc, DateTime.utc(2026, 11, 7));
    });

    test('edited draft offers originals only and never preselects them', () async {
      final edited = primary.copyWith(
        lines: [
          primary.lines.first.copyWith(text: 'edited line'),
          primary.lines.last,
        ],
      );
      final hint = await loader.preview(
        projectId: id,
        expectedProjectRevision: revision,
        draft: edited,
      );
      expect(
        hint.status,
        ProjectProofreadEvidenceHintStatus.readOnlyOriginalPair,
      );
      expect(hint.shouldOffer, isTrue);
      expect(hint.shouldSelectByDefault, isFalse);
    });

    test('unverified, missing and malformed evidence are never preselected',
        () async {
      await save(evidence());
      final unverified = await loader.preview(
        projectId: id,
        expectedProjectRevision: revision,
        draft: primary,
      );
      expect(
        unverified.status,
        ProjectProofreadEvidenceHintStatus.unverifiedAudio,
      );
      expect(unverified.shouldOffer, isFalse);

      await save(null);
      final missing = await loader.preview(
        projectId: id,
        expectedProjectRevision: revision,
        draft: primary,
      );
      expect(missing.status, ProjectProofreadEvidenceHintStatus.notFound);
      expect(missing.shouldOffer, isFalse);

      await save({'schemaVersion': 99});
      final malformed = await loader.preview(
        projectId: id,
        expectedProjectRevision: revision,
        draft: primary,
      );
      expect(malformed.status, ProjectProofreadEvidenceHintStatus.invalid);
      expect(malformed.shouldSelectByDefault, isFalse);
    });

    test('revision mismatch does not read stale project hints', () async {
      final hint = await loader.preview(
        projectId: id,
        expectedProjectRevision: revision - 1,
        draft: primary,
      );
      expect(hint.status, ProjectProofreadEvidenceHintStatus.projectChanged);
      expect(hint.shouldOffer, isFalse);
    });

    test('nonzero draft offset cannot select absolute-time snapshots', () async {
      final shifted = primary.copyWith(
        globalOffset: const Duration(milliseconds: 1),
      );
      final hint = await loader.preview(
        projectId: id,
        expectedProjectRevision: revision,
        draft: shifted,
      );
      expect(
        hint.status,
        ProjectProofreadEvidenceHintStatus.unsupportedOffsets,
      );
      expect(hint.shouldSelectByDefault, isFalse);
    });
  });

  group('Whisper raw JSON artifact cross-check', () {
    Future<File> writeWhisperArtifact({String text = 'another line'}) async {
      final file = File('${root.path}/whisper-second-opinion.json');
      await file.writeAsString(
        jsonEncode({
          'result': {'language': 'en'},
          'transcription': [
            {
              'text': text,
              'offsets': {'from': 0, 'to': 2000},
              'tokens': [
                {'text': text, 'p': 1.0},
              ],
            },
          ],
        }),
      );
      return file;
    }

    test('reads the Whisper path only when it matches the verified snapshot',
        () async {
      final artifactFile = await writeWhisperArtifact();
      await save(
        evidence(sourceHash: hash),
        extraMetadata: {'whisperRawJsonPath': artifactFile.path},
      );
      var reads = 0;
      loader = VerifiedProjectProofreadEvidenceLoader(
        projects: repo,
        readWhisperArtifact: (path) async {
          reads++;
          return const WhisperJsonArtifactReader().read(path);
        },
      );

      final result = await load();

      expect(reads, 1);
      expect(result.status, ProjectProofreadEvidenceStatus.available);
      expect(result.secondary!.lines.single.text, 'another line');
      expect(result.secondary!.metadata['rawJsonPath'], artifactFile.path);
    });

    test('ignores a stale or replaced Whisper artifact and keeps the snapshot',
        () async {
      final artifactFile = await writeWhisperArtifact(text: 'stale lyric');
      await save(
        evidence(sourceHash: hash),
        extraMetadata: {'whisperRawJsonPath': artifactFile.path},
      );

      final result = await load();

      expect(result.status, ProjectProofreadEvidenceStatus.available);
      expect(result.secondary!.lines.single.text, 'another line');
      expect(result.secondary!.metadata, isEmpty);
    });

    test('requires every parsed line field to match the verified snapshot', () async {
      final artifactFile = await writeWhisperArtifact();
      final variants = [
        secondary.copyWith(
          lines: [secondary.lines.single.copyWith(startTime: const Duration(milliseconds: 1))],
        ),
        secondary.copyWith(
          lines: [secondary.lines.single.copyWith(confidence: 99)],
        ),
        secondary.copyWith(
          lines: [
            secondary.lines.single.copyWith(
              confidenceSource: LyricConfidenceSource.heuristic,
            ),
          ],
        ),
        secondary.copyWith(
          lines: [secondary.lines.single.copyWith(isChorus: true)],
        ),
        secondary.copyWith(
          lines: [secondary.lines.single.copyWith(id: 'stored-line')],
        ),
      ];

      for (final snapshot in variants) {
        await save(
          evidence(sourceHash: hash, secondaryDoc: snapshot),
          extraMetadata: {'whisperRawJsonPath': artifactFile.path},
        );

        final result = await load();

        expect(result.status, ProjectProofreadEvidenceStatus.available);
        expect(result.secondary!.lines.single.toJson(),
            snapshot.lines.single.toJson());
        expect(result.secondary!.metadata, isEmpty);
      }
    });

    test('missing or failed raw reads fall back to the inline snapshot', () async {
      await save(evidence(sourceHash: hash));
      final missingPathResult = await load();
      expect(missingPathResult.status, ProjectProofreadEvidenceStatus.available);
      expect(missingPathResult.secondary!.toJson(), secondary.toJson());

      final artifactFile = await writeWhisperArtifact();
      await save(
        evidence(sourceHash: hash),
        extraMetadata: {'whisperRawJsonPath': artifactFile.path},
      );
      loader = VerifiedProjectProofreadEvidenceLoader(
        projects: repo,
        readWhisperArtifact: (_) async =>
            throw const FileSystemException('simulated read failure'),
      );

      final failedReadResult = await load();
      expect(failedReadResult.status, ProjectProofreadEvidenceStatus.available);
      expect(failedReadResult.secondary!.toJson(), secondary.toJson());
    });

    test('does not interpret the Whisper path as a Qwen transcript', () async {
      final artifactFile = await writeWhisperArtifact();
      await save(
        evidence(
          sourceHash: hash,
          first: 'whisper.cpp-large-v3',
          second: 'qwen3-asr-1.7b',
        ),
        extraMetadata: {'whisperRawJsonPath': artifactFile.path},
      );
      var reads = 0;
      loader = VerifiedProjectProofreadEvidenceLoader(
        projects: repo,
        readWhisperArtifact: (path) async {
          reads++;
          return const WhisperJsonArtifactReader().read(path);
        },
      );

      final result = await load();

      expect(reads, 0);
      expect(result.status, ProjectProofreadEvidenceStatus.available);
      expect(result.secondaryEngine, 'qwen3-asr-1.7b');
      expect(result.secondary!.metadata, isEmpty);
    });
  });
}

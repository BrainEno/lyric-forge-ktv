import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/project_proofread_evidence.dart';
import 'package:lyric_forge_ktv/features/project/data/repositories/file_project_repository.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/asr_evidence_audio_verifier.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/project_proofread_evidence_loader.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/independent_asr_evidence.dart';

const primary = LyricDocument(language: 'en', lines: [
  LyricLine(id: 'a', text: 'first line', startTime: Duration.zero, endTime: Duration(seconds: 2), confidence: 90, confidenceSource: LyricConfidenceSource.model),
  LyricLine(id: 'b', text: 'second line', startTime: Duration(seconds: 2), endTime: Duration(seconds: 4)),
]);
const secondary = LyricDocument(language: 'en', lines: [
  LyricLine(text: 'another line', startTime: Duration.zero, endTime: Duration(seconds: 2)),
]);

void main() {
  late Directory root;
  late File audio;
  late File vocal;
  late FileProjectRepository repo;
  late String id;
  late int revision;
  late VerifiedProjectProofreadEvidenceLoader loader;
  final hash = sha256.convert([1, 2, 3]).toString();

  Map<String, dynamic> evidence({String? sourceHash, LyricDocument primaryDoc = primary, LyricDocument secondaryDoc = secondary, String first = 'qwen3-asr-1.7b', String second = 'whisper.cpp-large-v3'}) => IndependentAsrEvidence(
    capturedAt: DateTime.utc(2026, 11, 7), sourceAudioSha256: sourceHash,
    primary: IndependentAsrTranscript(engine: first, document: primaryDoc),
    secondary: IndependentAsrTranscript(engine: second, document: secondaryDoc),
  ).toJson();

  Future<void> save(Object? raw, {LyricDocument doc = primary}) async {
    final project = (await repo.getProjectById(id))!;
    final updated = await repo.updateProject(project.copyWith(lyricDocument: doc.copyWith(metadata: raw == null ? {} : {IndependentAsrEvidence.metadataKey: raw})));
    revision = updated.revision;
  }

  Future<ProjectProofreadEvidenceResult> load({LyricDocument doc = primary, int? expected}) => loader.load(projectId: id, expectedProjectRevision: expected ?? revision, draft: doc);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('proofread-evidence-');
    audio = File('${root.path}/original.wav');
    vocal = File('${root.path}/vocal.wav');
    await audio.writeAsBytes([1, 2, 3]);
    repo = FileProjectRepository(rootDirectory: root);
    final created = await repo.createProject(name: 'Song');
    id = created.id;
    final updated = await repo.updateProject(created.copyWith(audioAsset: AudioAsset(originalPath: audio.path, vocalPath: vocal.path, format: 'wav'), lyricDocument: primary));
    revision = updated.revision;
    loader = VerifiedProjectProofreadEvidenceLoader(projects: repo);
    await save(evidence(sourceHash: hash));
  });
  tearDown(() async => root.delete(recursive: true));

  test('matching primary and bytes expose only an ephemeral second transcript', () async {
    final before = (await repo.getProjectById(id))!.toJson();
    final result = await load();
    expect(result.status, ProjectProofreadEvidenceStatus.available);
    expect(result.secondary!.toJson(), secondary.toJson());
    expect(result.secondaryEngine, 'whisper.cpp-large-v3');
    expect(result.capturedAtUtc, DateTime.utc(2026, 11, 7));
    expect((await repo.getProjectById(id))!.toJson(), before);
  });

  test('either engine can be primary', () async {
    await save(evidence(sourceHash: hash, first: 'whisper.cpp-large-v3', second: 'qwen3-asr-1.7b'));
    expect((await load()).secondaryEngine, 'qwen3-asr-1.7b');
  });

  test('absent, malformed, duplicate and unknown engines are rejected', () async {
    await save(null);
    expect((await load()).status, ProjectProofreadEvidenceStatus.missingEvidence);
    await save({'schemaVersion': 5});
    expect((await load()).status, ProjectProofreadEvidenceStatus.invalidEvidence);
    for (final engine in ['qwen3-asr-1.7b', 'other-engine', 'whisper.cpp-/private/path']) {
      await save(evidence(sourceHash: hash, second: engine));
      expect((await load()).status, ProjectProofreadEvidenceStatus.invalidEvidence);
    }
  });

  test('old snapshot, changed bytes and missing files are not matches', () async {
    await save(evidence());
    expect((await load()).status, ProjectProofreadEvidenceStatus.unverifiedAudio);
    await save(evidence(sourceHash: hash));
    await audio.writeAsBytes([3, 2, 1]);
    expect((await load()).status, ProjectProofreadEvidenceStatus.audioChanged);
    await audio.delete();
    expect((await load()).status, ProjectProofreadEvidenceStatus.audioUnavailable);
  });

  test('uses the actual selected stem, even when another file matches', () async {
    await vocal.writeAsBytes([4, 5, 6]);
    expect((await load()).status, ProjectProofreadEvidenceStatus.audioChanged);
    await vocal.writeAsBytes([1, 2, 3]);
    expect((await load()).status, ProjectProofreadEvidenceStatus.available);
  });

  test('rejects changed text, timing, confidence, order, count and language', () async {
    final first = primary.lines.first;
    final variants = [
      primary.copyWith(lines: [first.copyWith(text: 'edited'), primary.lines.last]),
      primary.copyWith(lines: [first.copyWith(startTime: const Duration(milliseconds: 1)), primary.lines.last]),
      primary.copyWith(lines: [first.copyWith(endTime: const Duration(milliseconds: 1999)), primary.lines.last]),
      primary.copyWith(lines: [first.copyWith(confidence: 88), primary.lines.last]),
      primary.copyWith(lines: [first.copyWith(confidenceSource: LyricConfidenceSource.heuristic), primary.lines.last]),
      primary.copyWith(lines: primary.lines.reversed.toList()),
      primary.copyWith(lines: [first]),
      primary.copyWith(language: 'zh'),
    ];
    for (final doc in variants) {
      expect((await load(doc: doc)).status, ProjectProofreadEvidenceStatus.draftChanged);
    }
  });

  test('ids and chorus labels do not affect independent text and timing', () async {
    final doc = primary.copyWith(lines: [primary.lines.first.copyWith(id: 'new', isChorus: true), primary.lines.last]);
    expect((await load(doc: doc)).status, ProjectProofreadEvidenceStatus.available);
  });

  test('nonzero offsets and invalid temporal ordering fail closed', () async {
    expect((await load(doc: primary.copyWith(globalOffset: const Duration(milliseconds: 1)))).status, ProjectProofreadEvidenceStatus.unsupportedOffsets);
    await save(evidence(sourceHash: hash, secondaryDoc: secondary.copyWith(globalOffset: const Duration(seconds: 1))));
    expect((await load()).status, ProjectProofreadEvidenceStatus.unsupportedOffsets);
    final unordered = primary.copyWith(lines: primary.lines.reversed.toList());
    await save(evidence(sourceHash: hash, secondaryDoc: unordered));
    expect((await load()).status, ProjectProofreadEvidenceStatus.invalidEvidence);
    await save(evidence(sourceHash: hash, secondaryDoc: secondary.copyWith(lines: [secondary.lines.first.copyWith(text: '  ')])));
    expect((await load()).status, ProjectProofreadEvidenceStatus.invalidEvidence);
  });

  test('stale project revision rejected before and after hashing', () async {
    expect((await load(expected: revision - 1)).status, ProjectProofreadEvidenceStatus.projectChanged);
    loader = VerifiedProjectProofreadEvidenceLoader(projects: repo, verifyAudio: ({required rawEvidence, required currentAudioPath}) async {
      final project = (await repo.getProjectById(id))!;
      await repo.updateProject(project.copyWith(name: 'changed'));
      return AsrEvidenceAudioStatus.audioMatches;
    });
    expect((await load()).status, ProjectProofreadEvidenceStatus.projectChanged);
  });

  test('detects selected input changing during hash', () async {
    loader = VerifiedProjectProofreadEvidenceLoader(projects: repo, verifyAudio: ({required rawEvidence, required currentAudioPath}) async {
      await vocal.writeAsBytes([1, 2, 3]);
      return AsrEvidenceAudioStatus.audioMatches;
    });
    expect((await load()).status, ProjectProofreadEvidenceStatus.audioSelectionChanged);
  });

  test('propagates each verifier outcome without exposing a transcript', () async {
    final cases = {
      AsrEvidenceAudioStatus.missingEvidence: ProjectProofreadEvidenceStatus.missingEvidence,
      AsrEvidenceAudioStatus.invalidEvidence: ProjectProofreadEvidenceStatus.invalidEvidence,
      AsrEvidenceAudioStatus.unverified: ProjectProofreadEvidenceStatus.unverifiedAudio,
      AsrEvidenceAudioStatus.audioUnavailable: ProjectProofreadEvidenceStatus.audioUnavailable,
      AsrEvidenceAudioStatus.audioChanged: ProjectProofreadEvidenceStatus.audioChanged,
    };
    for (final entry in cases.entries) {
      loader = VerifiedProjectProofreadEvidenceLoader(projects: repo, verifyAudio: ({required rawEvidence, required currentAudioPath}) async => entry.key);
      final result = await load();
      expect(result.status, entry.value);
      expect(result.secondary, isNull);
    }
  });
}

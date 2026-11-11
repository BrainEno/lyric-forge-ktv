import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/reference_lyric_input.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/reference_lyric_line.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/timing_provenance.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/apply_reference_alignment_use_case.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/reference_alignment_provenance_builder.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/reference_alignment_restore_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

LyricLine line(String text, int start, int end, {String? id}) => LyricLine(
  id: id,
  text: text,
  startTime: Duration(seconds: start),
  endTime: Duration(seconds: end),
  confidence: 42,
);

LyricDocument draft(
  List<LyricLine> lines, {
  Map<String, dynamic> metadata = const {},
}) => LyricDocument(
  language: 'zh',
  lines: lines,
  globalOffset: const Duration(milliseconds: 100),
  metadata: metadata,
);

ReferenceLyricInput input(
  List<ReferenceLyricLine> lines, {
  bool timed = false,
  String? sourcePath,
  List<String> warnings = const [],
}) => ReferenceLyricInput(
  lines: lines,
  timed: timed,
  format: timed ? 'lrc' : 'plain',
  sourcePath: sourcePath,
  offset: const Duration(milliseconds: 250),
  title: 'Song',
  artist: 'Artist',
  warnings: warnings,
);

ReferenceAlignmentProposal apply(
  ReferenceAlignmentPlan plan, {
  Set<int> accepted = const {},
  Set<int> inserted = const {},
  Set<int> overrides = const {},
  bool timing = false,
}) => plan.apply(
  acceptedReferenceIndices: accepted,
  acceptedMissingReferenceIndices: inserted,
  overriddenAsrLineIndices: overrides,
  applyReferenceTiming: timing,
);

void main() {
  const useCase = ApplyReferenceAlignmentUseCase();
  final now = DateTime.utc(2026, 11, 7, 12, 0);
  late LyricDocument original;
  late ReferenceLyricInput plain;
  late ReferenceLyricInput timed;
  setUp(() {
    original = draft(
      [line('月亮代表我的星', 1, 5, id: 'first')],
      metadata: {'custom': 'preserved'},
    );
    plain = input([const ReferenceLyricLine(text: '月亮代表我的心')]);
    timed = input([
      const ReferenceLyricLine(
        text: '月亮代表我的心',
        startTime: Duration(seconds: 2),
        endTime: Duration(seconds: 4),
      ),
    ], timed: true);
  });

  group('preparing review', () {
    test('creates alignment without touching original', () {
      final before = jsonEncode(original.toJson());
      final plan = useCase.prepare(draft: original, input: plain);
      expect(plan.isEmpty, isFalse);
      expect(plan.alignment.entries.single.referenceText, '月亮代表我的心');
      expect(plan.minimumSimilarity, 0.8);
      expect(plan.timingUnavailableReason, isNull);
      expect(jsonEncode(original.toJson()), before);
    });

    test('empty reference gives no review entries', () {
      final plan = useCase.prepare(draft: original, input: input([]));
      expect(plan.isEmpty, isTrue);
    });

    test('untimed reference does not report timed-input failure', () {
      final plan = useCase.prepare(
        draft: original,
        input: plain,
        protectedLineIndices: {0},
      );
      expect(plan.timingUnavailableReason, isNull);
    });

    test('fully timed matching structure offers timing', () {
      final plan = useCase.prepare(draft: original, input: timed);
      expect(plan.timingUnavailableReason, isNull);
    });

    test('partially timed reference takes precedence over protection', () {
      final document = draft([line('第一句歌词', 0, 4), line('第三句歌词', 8, 12)]);
      final reference = input([
        const ReferenceLyricLine(
          text: '第一句歌词',
          startTime: Duration(seconds: 1),
        ),
        const ReferenceLyricLine(text: '第三句歌词'),
      ], timed: true);
      final plan = useCase.prepare(
        draft: document,
        input: reference,
        protectedLineIndices: {0},
      );
      expect(
        plan.timingUnavailableReason,
        ReferenceTimingUnavailableReason.partiallyTimed,
      );
    });

    test('missing reference line blocks timeline replacement', () {
      final document = draft([line('第一句歌词', 0, 4), line('第三句歌词', 8, 12)]);
      final reference = input([
        const ReferenceLyricLine(
          text: '第一句歌词',
          startTime: Duration(seconds: 1),
        ),
        const ReferenceLyricLine(
          text: '第二句歌词',
          startTime: Duration(seconds: 5),
        ),
        const ReferenceLyricLine(
          text: '第三句歌词',
          startTime: Duration(seconds: 9),
        ),
      ], timed: true);
      final plan = useCase.prepare(draft: document, input: reference);
      expect(plan.alignment.missingReferenceIndices, [1]);
      expect(
        plan.timingUnavailableReason,
        ReferenceTimingUnavailableReason.structuralMismatch,
      );
    });

    test('extra draft line blocks timeline replacement', () {
      final document = draft([line('月亮代表我的星', 1, 5), line('第二句歌词', 6, 9)]);
      final plan = useCase.prepare(draft: document, input: timed);
      expect(
        plan.timingUnavailableReason,
        ReferenceTimingUnavailableReason.structuralMismatch,
      );
    });

    test('protected rows block timing for an otherwise matched reference', () {
      final plan = useCase.prepare(
        draft: original,
        input: timed,
        protectedLineIndices: {0},
      );
      expect(
        plan.timingUnavailableReason,
        ReferenceTimingUnavailableReason.protectedLines,
      );
    });

    test('copies the protection set and exposes it read-only', () {
      final protection = <int>{0};
      final plan = useCase.prepare(
        draft: original,
        input: plain,
        protectedLineIndices: protection,
      );
      protection.clear();
      expect(plan.protectedLineIndices, {0});
      expect(() => plan.protectedLineIndices.clear(), throwsUnsupportedError);
      expect(apply(plan, accepted: {0}).result.hasChanges, isFalse);
    });
  });

  group('reviewed application', () {
    test('only explicitly selected text is corrected', () {
      final plan = useCase.prepare(draft: original, input: plain);
      final selected = apply(plan, accepted: {0});
      expect(selected.result.document.lines.single.text, '月亮代表我的心');
      expect(
        selected.result.document.lines.single.startTime,
        const Duration(seconds: 1),
      );
      expect(selected.result.corrections.single.asrLineIndex, 0);
      expect(apply(plan).result.hasChanges, isFalse);
      expect(original.lines.single.text, '月亮代表我的星');
    });

    test('protected line stays unchanged until explicitly overridden', () {
      final plan = useCase.prepare(
        draft: original,
        input: plain,
        protectedLineIndices: {0},
      );
      final skipped = apply(plan, accepted: {0});
      expect(skipped.result.hasChanges, isFalse);
      expect(skipped.result.skippedManuallyEditedIndices, [0]);
      final overridden = apply(plan, accepted: {0}, overrides: {0});
      expect(overridden.result.document.lines.single.text, '月亮代表我的心');
      expect(overridden.overriddenManuallyEditedCount, 1);
    });

    test(
      'reviewed reference timing is applied and resets offset on commit',
      () {
        final plan = useCase.prepare(draft: original, input: timed);
        final proposal = apply(plan, accepted: {0}, timing: true);
        expect(proposal.result.timingUpdatedCount, 1);
        expect(proposal.result.document.globalOffset, original.globalOffset);
        final committed = proposal.materialize(appliedAt: now);
        expect(committed.lines.single.startTime, const Duration(seconds: 2));
        expect(committed.lines.single.endTime, const Duration(seconds: 4));
        expect(committed.globalOffset, Duration.zero);
        expect(original.globalOffset, const Duration(milliseconds: 100));
      },
    );

    test('no change materializes original without backup or provenance', () {
      final plan = useCase.prepare(draft: original, input: plain);
      final proposal = apply(plan);
      expect(proposal.result.hasChanges, isFalse);
      expect(proposal.materialize(appliedAt: now), same(original));
      expect(
        original.metadata.containsKey(kReferenceAlignmentBackupKey),
        isFalse,
      );
    });

    test(
      'selected missing line is inserted with new stable ID and provenance',
      () {
        final document = draft([
          line('第一句歌词', 0, 4, id: 'first'),
          line('第三句歌词', 8, 12, id: 'third'),
        ]);
        final reference = input([
          const ReferenceLyricLine(text: '第一句歌词'),
          const ReferenceLyricLine(text: '第二句歌词'),
          const ReferenceLyricLine(text: '第三句歌词'),
        ]);
        final plan = useCase.prepare(draft: document, input: reference);
        expect(plan.alignment.missingReferenceIndices, [1]);
        final proposal = apply(plan, inserted: {1});
        expect(proposal.result.insertions, hasLength(1));
        final result = proposal.materialize(appliedAt: now);
        expect(result.lines.map((row) => row.text), [
          '第一句歌词',
          '第二句歌词',
          '第三句歌词',
        ]);
        expect(result.lines.first.id, 'first');
        expect(result.lines.last.id, 'third');
        expect(result.lines[1].id, isNotNull);
        final provenance =
            result.metadata[ReferenceAlignmentProvenanceBuilder.metadataKey]
                as Map;
        expect(
          (provenance['insertions'] as List).single['lineId'],
          result.lines[1].id,
        );
        expect(
          (provenance['insertions'] as List).single['appliedLineIndex'],
          1,
        );
        expect(document.lines, hasLength(2));
      },
    );

    test('audio duration reaches timeline validation', () {
      final reference = input([
        const ReferenceLyricLine(
          text: '月亮代表我的星',
          startTime: Duration(seconds: 20),
          endTime: Duration(seconds: 22),
        ),
      ], timed: true);
      final plan = useCase.prepare(
        draft: original,
        input: reference,
        audioDuration: const Duration(seconds: 10),
      );
      final proposal = apply(plan, timing: true);
      expect(
        proposal.result.timelineComparison!.hasIntroducedSeriousIssues,
        isTrue,
      );
      expect(original.lines.single.startTime, const Duration(seconds: 1));
    });
  });

  group('backup and provenance', () {
    test(
      'materialized document keeps metadata and a restorable pre-change backup',
      () {
        final before = jsonEncode(original.toJson());
        final plan = useCase.prepare(draft: original, input: plain);
        final committed = apply(
          plan,
          accepted: {0},
        ).materialize(appliedAt: now);
        expect(jsonEncode(original.toJson()), before);
        expect(committed.metadata['custom'], 'preserved');
        final backup = committed.metadata[kReferenceAlignmentBackupKey] as Map;
        expect(backup['createdAt'], now.toIso8601String());
        expect(backup['source'], 'paste');
        expect(backup['lineCount'], 1);
        expect(backup['referenceOffsetMs'], 250);
        final restored = const ReferenceAlignmentRestoreService().restore(
          committed,
          now: now,
        );
        expect(restored, isA<ReferenceAlignmentRestoreSuccess>());
        final restoredDocument =
            (restored as ReferenceAlignmentRestoreSuccess).document;
        expect(restoredDocument.lines.single.text, '月亮代表我的星');
        expect(restoredDocument.globalOffset, original.globalOffset);
        expect(restoredDocument.metadata['custom'], 'preserved');
      },
    );

    test('new backup does not recursively contain the old backup', () {
      final withOldBackup = draft(
        original.lines,
        metadata: {
          kReferenceAlignmentBackupKey: {'old': 'backup'},
          'custom': 'keep',
        },
      );
      final plan = useCase.prepare(draft: withOldBackup, input: plain);
      final result = apply(plan, accepted: {0}).materialize(appliedAt: now);
      final backup = result.metadata[kReferenceAlignmentBackupKey] as Map;
      final document = backup['document'] as Map;
      expect(
        (document['metadata'] as Map).containsKey(kReferenceAlignmentBackupKey),
        isFalse,
      );
      expect((document['metadata'] as Map)['custom'], 'keep');
      expect(withOldBackup.metadata[kReferenceAlignmentBackupKey], {
        'old': 'backup',
      });
    });

    test(
      'file source, review counts, and stable correction IDs are recorded',
      () {
        final reference = input(
          plain.lines,
          sourcePath: '/tmp/歌词.txt',
          warnings: ['warning'],
        );
        final plan = useCase.prepare(
          draft: original,
          input: reference,
          protectedLineIndices: {0},
        );
        final accepted = <int>{0};
        final overridden = <int>{0};
        final proposal = apply(plan, accepted: accepted, overrides: overridden);
        accepted.clear();
        overridden.clear();
        final committed = proposal.materialize(appliedAt: now);
        final backup = committed.metadata[kReferenceAlignmentBackupKey] as Map;
        final provenance =
            committed.metadata[ReferenceAlignmentProvenanceBuilder.metadataKey]
                as Map;
        expect(backup['source'], 'file');
        expect(backup['sourcePath'], '/tmp/歌词.txt');
        expect(provenance['referenceWarningCount'], 1);
        expect(provenance['acceptedReferenceCount'], 1);
        expect(provenance['overriddenManuallyEditedCount'], 1);
        expect(provenance['indexBase'], 'pre-application');
        expect((provenance['corrections'] as List).single['lineId'], 'first');
      },
    );

    test('manual timing provenance is not overwritten by reference timing', () {
      final withProvenance = draft(
        original.lines,
        metadata: {
          kLyricTimingProvenanceKey: {
            'first': LyricTimingProvenance.manual.name,
          },
        },
      );
      final plan = useCase.prepare(draft: withProvenance, input: timed);
      final committed = apply(plan, timing: true).materialize(appliedAt: now);
      final provenance =
          committed.metadata[ReferenceAlignmentProvenanceBuilder.metadataKey]
              as Map;
      expect(
        (provenance[kLyricTimingProvenanceKey] as Map)['first'],
        LyricTimingProvenance.manual.name,
      );
    });
  });
}

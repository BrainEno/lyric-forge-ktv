import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/reference_alignment_restore_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

void main() {
  const service = ReferenceAlignmentRestoreService();

  final backupDocument = LyricDocument(
    language: 'zh',
    lines: const [
      LyricLine(
        text: '月亮代表我的心',
        startTime: Duration(seconds: 1),
        endTime: Duration(seconds: 5),
        confidence: 88,
      ),
      LyricLine(
        text: '今天天气真好',
        startTime: Duration(seconds: 5),
        endTime: Duration(seconds: 9),
      ),
    ],
    globalOffset: const Duration(milliseconds: 300),
    metadata: <String, dynamic>{
      'referenceAlignment': <String, dynamic>{
        'source': 'reference-alignment',
        'appliedAt': '2026-10-20T10:00:00.000',
      },
    },
  );

  Map<String, dynamic> validBackup() => <String, dynamic>{
    'createdAt': '2026-10-20T11:00:00.000',
    'reason': 'reference-alignment',
    'source': 'paste',
    'format': 'lrc',
    'timed': true,
    'referenceOffsetMs': 120,
    'lineCount': 2,
    'document': backupDocument.toJson(),
  };

  LyricDocument currentDocument([Map<String, dynamic>? backup]) {
    return LyricDocument(
      language: 'zh',
      lines: const [
        LyricLine(
          text: '月亮代表我的星（已改）',
          startTime: Duration(seconds: 1),
          endTime: Duration(seconds: 5),
        ),
      ],
      metadata: <String, dynamic>{
        kReferenceAlignmentBackupKey: backup ?? validBackup(),
      },
    );
  }

  group('probeBackup', () {
    test('备份存在且可解析时返回摘要', () {
      final probe = service.probeBackup(currentDocument());

      expect(probe, isA<ReferenceAlignmentBackupAvailable>());
      final summary = (probe as ReferenceAlignmentBackupAvailable).summary;
      expect(summary.createdAt, DateTime.parse('2026-10-20T11:00:00.000'));
      expect(summary.reason, 'reference-alignment');
      expect(summary.source, 'paste');
      expect(summary.sourcePath, isNull);
      expect(summary.format, 'lrc');
      expect(summary.lineCount, 2);
    });

    test('备份缺失时返回 missing', () {
      const document = LyricDocument(language: 'zh', lines: []);

      final probe = service.probeBackup(document);
      expect(probe, isA<ReferenceAlignmentBackupUnavailable>());
      expect(
        (probe as ReferenceAlignmentBackupUnavailable).issue,
        ReferenceAlignmentBackupIssue.missing,
      );
    });

    test('备份结构类型错误时返回 invalidShape', () {
      final badType = currentDocument({...validBackup(), 'lineCount': 'two'});
      final notAMap = currentDocument({...validBackup(), 'document': 42});

      for (final document in [badType, notAMap]) {
        final probe = service.probeBackup(document);
        expect(
          (probe as ReferenceAlignmentBackupUnavailable).issue,
          ReferenceAlignmentBackupIssue.invalidShape,
        );
      }
    });

    test('备份文档 JSON 损坏时返回 corruptDocument', () {
      final document = currentDocument({
        ...validBackup(),
        'document': <String, dynamic>{'language': 'zh', 'lines': 'nope'},
      });

      final probe = service.probeBackup(document);
      expect(
        (probe as ReferenceAlignmentBackupUnavailable).issue,
        ReferenceAlignmentBackupIssue.corruptDocument,
      );
    });

    test('document 行数与记录不一致时返回 lineCountMismatch', () {
      final document = currentDocument({...validBackup(), 'lineCount': 5});

      final probe = service.probeBackup(document);
      expect(
        (probe as ReferenceAlignmentBackupUnavailable).issue,
        ReferenceAlignmentBackupIssue.lineCountMismatch,
      );
    });
  });

  group('restore', () {
    test('正常恢复用备份文档替换当前文档并写入溯源', () {
      final input = currentDocument();
      final result = service.restore(
        input,
        now: DateTime.parse('2026-10-20T12:00:00.000'),
      );

      expect(result, isA<ReferenceAlignmentRestoreSuccess>());
      final restored = (result as ReferenceAlignmentRestoreSuccess).document;

      expect(restored.lines, hasLength(2));
      expect(restored.lines.first.text, '月亮代表我的心');
      expect(restored.lines.first.confidence, 88);
      expect(restored.globalOffset, const Duration(milliseconds: 300));

      expect(restored.metadata[kReferenceAlignmentBackupKey], isNull);
      expect(restored.metadata['referenceAlignment'], {
        'source': 'reference-alignment',
        'appliedAt': '2026-10-20T10:00:00.000',
      });

      final provenance =
          restored.metadata[kReferenceAlignmentRestoreKey]!
              as Map<String, dynamic>;
      expect(provenance['source'], 'reference-alignment-restore');
      expect(provenance['restoredAt'], '2026-10-20T12:00:00.000');
      expect(provenance['backupCreatedAt'], '2026-10-20T11:00:00.000');
      expect(provenance['backupReason'], 'reference-alignment');
      expect(provenance['backupLineCount'], 2);
      expect(provenance['restoredLineCount'], 2);
    });

    test('恢复不修改入参文档', () {
      final input = currentDocument();
      final before = input.toJson();

      service.restore(input, now: DateTime.parse('2026-10-20T12:00:00.000'));

      expect(input.toJson(), equals(before));
      expect(input.metadata[kReferenceAlignmentBackupKey], isNotNull);
    });

    test('恢复成功后备份键被消耗，再次探测为 missing', () {
      final result = service.restore(currentDocument());

      final restored = (result as ReferenceAlignmentRestoreSuccess).document;
      final secondProbe = service.probeBackup(restored);
      expect(secondProbe, isA<ReferenceAlignmentBackupUnavailable>());
      expect(
        (secondProbe as ReferenceAlignmentBackupUnavailable).issue,
        ReferenceAlignmentBackupIssue.missing,
      );

      final secondRestore = service.restore(restored);
      expect(secondRestore, isA<ReferenceAlignmentRestoreFailure>());
      expect(
        (secondRestore as ReferenceAlignmentRestoreFailure).issue,
        ReferenceAlignmentBackupIssue.missing,
      );
    });

    test('备份校验失败时返回对应 issue 且不产出文档', () {
      const cases = <(Map<String, dynamic>, ReferenceAlignmentBackupIssue)>[
        ({'lineCount': 'two'}, ReferenceAlignmentBackupIssue.invalidShape),
        ({'lineCount': 5}, ReferenceAlignmentBackupIssue.lineCountMismatch),
      ];

      for (final (overrides, expected) in cases) {
        final result = service.restore(
          currentDocument({...validBackup(), ...overrides}),
        );
        expect(result, isA<ReferenceAlignmentRestoreFailure>());
        expect((result as ReferenceAlignmentRestoreFailure).issue, expected);
      }

      final missing = service.restore(
        const LyricDocument(language: 'zh', lines: []),
      );
      expect(
        (missing as ReferenceAlignmentRestoreFailure).issue,
        ReferenceAlignmentBackupIssue.missing,
      );
    });
  });
}

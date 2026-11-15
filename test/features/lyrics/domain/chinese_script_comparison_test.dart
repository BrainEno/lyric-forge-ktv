import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/reference_lyric_line.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/lyric_tokenizer.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/reference_token_aligner.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_alignment_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_review_priority_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/asr_text_comparison.dart';

/// Every comparison path treats simplified and traditional script as the same
/// lyric (issue #450), while the written form stays visible where the user
/// decides what to keep.
void main() {
  LyricLine line(String text, {int startMs = 0, int endMs = 4000}) => LyricLine(
    text: text,
    startTime: Duration(milliseconds: startMs),
    endTime: Duration(milliseconds: endMs),
    confidence: 90,
  );

  group('tokenizer', () {
    test('folds script by default', () {
      const tokenizer = LyricTokenizer();
      expect(tokenizer.tokenize('頭髮飄在風裡'), tokenizer.tokenize('头发飘在风里'));
      expect(tokenizer.normalize('我愛你'), '我 爱 你');
    });

    test('can keep the written form', () {
      const tokenizer = LyricTokenizer(foldChineseScript: false);
      expect(tokenizer.tokenize('我愛你'), ['我', '愛', '你']);
    });

    test('reference token alignment anchors across scripts', () {
      final result = const ReferenceTokenAligner().align(
        referenceText: '後來我總算學會了如何去愛',
        draftText: '后来我总算学会了如何去爱',
      );
      expect(result.isComplete, isTrue);
      expect(result.matchedReferenceTokenCount, result.referenceTokenCount);
      expect(result.matches.every((match) => match.similarity == 1), isTrue);
    });
  });

  group('reference alignment', () {
    const service = LyricAlignmentService();

    test('pairs lines across scripts but still offers the written form', () {
      final result = service.align(
        document: LyricDocument(
          language: 'zh',
          lines: [line('我爱你'), line('你在哪里', startMs: 4000, endMs: 8000)],
        ),
        referenceLines: const [
          ReferenceLyricLine(text: '我愛你'),
          ReferenceLyricLine(text: '你在哪里'),
        ],
      );

      expect(result.entries, hasLength(2));
      expect(result.entries[0].asrLineIndex, 0);
      expect(result.entries[0].similarity, 1.0);
      // Same lyric, different script: replacing adopts the reference script.
      expect(result.entries[0].status, ReferenceLineAlignmentStatus.replace);
      expect(result.entries[1].status, ReferenceLineAlignmentStatus.identical);
      expect(result.asrLines[0].status, AsrLineAlignmentStatus.toBeCorrected);
      expect(result.asrLines[1].status, AsrLineAlignmentStatus.matched);
    });

    test('normalizeLine folds unless asked not to', () {
      expect(LyricAlignmentService.normalizeLine('我愛你！'), '我爱你');
      expect(
        LyricAlignmentService.normalizeLine('我愛你！', foldChineseScript: false),
        '我愛你',
      );
      expect(LyricAlignmentService.lineSimilarity('為什麼', '为什么'), 1.0);
    });
  });

  group('dual-engine comparison', () {
    const comparison = AsrTextComparison();

    test('script differences are not disagreements', () {
      expect(comparison.similarity('頭髮飄在風裡', '头发飘在风里'), 1.0);
      expect(comparison.normalize('裏面的着急'), comparison.normalize('裡面的著急'));
    });

    test('real word differences still count', () {
      expect(comparison.similarity('头发飘在风里', '头发飘在雨里'), lessThan(1.0));
    });
  });

  group('review priority', () {
    const service = LyricReviewPriorityService();

    LyricDocument withCandidate(String primary, String alternative) =>
        LyricDocument(
          language: 'zh',
          lines: [line(primary)],
          metadata: {
            'fallbackCandidates': [
              {
                'lineIndex': 0,
                'primaryText': primary,
                'alternativeText': alternative,
              },
            ],
          },
        );

    test('engines differing only in script do not queue the line', () {
      expect(service.rank(withCandidate('头发飘在风里', '頭髮飄在風裡')), isEmpty);
    });

    test('engines differing in words still queue it', () {
      expect(service.rank(withCandidate('头发飘在风里', '头发飘在雨里')), isNotEmpty);
    });
  });
}

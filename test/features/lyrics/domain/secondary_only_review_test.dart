import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/lyric_review_queue.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/recognition_review_summary.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/secondary_only_suggestion.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_indexed_review_metadata.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_review_decision_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_review_priority_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

LyricLine _line(
  String text,
  int startMs,
  int endMs, {
  String? id,
  int confidence = 92,
  LyricConfidenceSource source = LyricConfidenceSource.model,
}) => LyricLine(
  id: id,
  text: text,
  startTime: Duration(milliseconds: startMs),
  endTime: Duration(milliseconds: endMs),
  confidence: confidence,
  confidenceSource: source,
);

const _suggestion = SecondaryOnlySuggestion(
  text: 'every window burning gold',
  startMs: 4000,
  endMs: 7000,
  engine: 'whisper.cpp-large-v3',
  engineConfidence: 88,
);

LyricDocument _fusedDocument({Map<String, dynamic> extra = const {}}) =>
    LyricDocument(
      language: 'en',
      lines: [
        _line('city lights are calling', 0, 3000, id: 'a'),
        _line(
          'every window burning gold',
          4000,
          7000,
          id: 'b',
          confidence: 60,
          source: LyricConfidenceSource.heuristic,
        ),
        _line('we run until the morning', 8000, 11000, id: 'c'),
      ],
      metadata: {
        'qualityMode': 'highestQuality',
        'primaryEngine': 'qwen3-asr-1.7b',
        'fallbackEngine': 'whisper.cpp-large-v3',
        'fallbackStatus': 'completed',
        'secondaryOnlyLineIndices': [1],
        'secondaryOnlyLineCount': 1,
        SecondaryOnlySuggestion.metadataKey: SecondaryOnlySuggestion.wrap([
          _suggestion,
        ]),
        ...extra,
      },
    );

void main() {
  group('SecondaryOnlySuggestion', () {
    test('resolves rows by exact text and timing, not by index', () {
      final document = _fusedDocument();
      expect(SecondaryOnlySuggestion.resolve(document).keys, [1]);

      // A row inserted above shifts the index; the record follows the row.
      final shifted = document.copyWith(
        lines: [
          _line('new intro', 0, 0 + 500, id: 'z'),
          ...document.lines,
        ],
      );
      expect(SecondaryOnlySuggestion.resolve(shifted).keys, [2]);
    });

    test('an edited row is no longer a suggestion', () {
      final document = _fusedDocument();
      final edited = document.copyWith(
        lines: [...document.lines]
          ..[1] = document.lines[1].copyWith(text: 'every window burns gold'),
      );
      expect(SecondaryOnlySuggestion.resolve(edited), isEmpty);

      final retimed = document.copyWith(
        lines: [...document.lines]
          ..[1] = document.lines[1].copyWith(
            startTime: const Duration(milliseconds: 4100),
          ),
      );
      expect(SecondaryOnlySuggestion.resolve(retimed), isEmpty);
    });

    test('malformed or foreign-version records are ignored', () {
      expect(
        SecondaryOnlySuggestion.read({
          SecondaryOnlySuggestion.metadataKey: {
            'version': 99,
            'entries': [_suggestion.toJson()],
          },
        }),
        isEmpty,
      );
      expect(
        SecondaryOnlySuggestion.read({
          SecondaryOnlySuggestion.metadataKey: {
            'version': SecondaryOnlySuggestion.version,
            'entries': [
              {'text': '', 'startMs': 0, 'endMs': 10},
              {'text': 'x', 'startMs': 10, 'endMs': 10},
              {'text': 'x', 'startMs': -1, 'endMs': 10},
              'nonsense',
              _suggestion.toJson(),
              _suggestion.toJson(),
            ],
          },
        }),
        [isA<SecondaryOnlySuggestion>()],
      );
    });

    test('shifting moves records into song time', () {
      final shifted = SecondaryOnlySuggestion.shiftMetadata({
        SecondaryOnlySuggestion.metadataKey: SecondaryOnlySuggestion.wrap([
          _suggestion,
        ]),
        'other': 1,
      }, const Duration(minutes: 3));
      final record = SecondaryOnlySuggestion.read(shifted).single;
      expect(record.startMs, 184000);
      expect(record.endMs, 187000);
      expect(record.engineConfidence, 88);
      expect(shifted['other'], 1);
      expect(
        SecondaryOnlySuggestion.shiftMetadata(const {
          'x': 1,
        }, const Duration(seconds: 1)),
        {'x': 1},
      );
    });
  });

  group('review priority', () {
    test('a pending suggestion is queued with its own reason', () {
      final ranked = const LyricReviewPriorityService().rank(_fusedDocument());
      final item = ranked.singleWhere((entry) => entry.lineIndex == 1);
      expect(
        item.reasons.map((reason) => reason.code),
        contains(LyricReviewPriorityReasonCode.secondaryOnlySuggestion),
      );
      expect(item.score, greaterThanOrEqualTo(25));
    });

    test('a confident suggestion still reaches the queue', () {
      final document = _fusedDocument();
      final confident = document.copyWith(
        lines: [...document.lines]
          ..[1] = document.lines[1].copyWith(
            confidence: 99,
            confidenceSource: LyricConfidenceSource.model,
          ),
      );
      final queue = LyricReviewQueue.build(confident);
      expect(queue.needsReview(1), isTrue);
    });

    test('keeping a suggestion (review decision) clears it from the queue', () {
      final reviewed = const LyricReviewDecisionService().setReviewed(
        _fusedDocument(),
        1,
        reviewed: true,
      );
      final queue = LyricReviewQueue.build(reviewed);
      expect(queue.needsReview(1), isFalse);
      // The row and its text are untouched by the decision.
      expect(reviewed.lines[1].text, 'every window burning gold');
    });
  });

  group('LyricIndexedReviewMetadata', () {
    Map<String, dynamic> metadata() => {
      'fallbackCandidates': [
        {'lineIndex': 0, 'alternativeText': 'zero'},
        {'lineIndex': 2, 'alternativeText': 'two'},
        {'lineIndex': 3, 'alternativeText': 'three'},
      ],
      'fallbackCandidateCount': 3,
      'fallbackAppliedCount': 1,
      'secondaryOnlyLineIndices': [1, 3],
      'secondaryOnlyLineCount': 2,
      'untouched': true,
    };

    test('deleting a row drops its evidence and shifts later rows', () {
      final result = LyricIndexedReviewMetadata.afterRowRemoved(metadata(), 2);
      expect(
        (result['fallbackCandidates'] as List).map(
          (entry) => (entry as Map)['lineIndex'],
        ),
        [0, 2],
      );
      expect(
        (result['fallbackCandidates'] as List).map(
          (entry) => (entry as Map)['alternativeText'],
        ),
        ['zero', 'three'],
      );
      expect(result['fallbackCandidateCount'], 2);
      expect(result['secondaryOnlyLineIndices'], [1, 2]);
      expect(result['secondaryOnlyLineCount'], 2);
      expect(result['untouched'], isTrue);
    });

    test('inserting a row shifts rows at and after it', () {
      final result = LyricIndexedReviewMetadata.afterRowInserted(metadata(), 1);
      expect(
        (result['fallbackCandidates'] as List).map(
          (entry) => (entry as Map)['lineIndex'],
        ),
        [0, 3, 4],
      );
      expect(result['secondaryOnlyLineIndices'], [2, 4]);
    });

    test('malformed candidate lists are dropped, never guessed', () {
      final result = LyricIndexedReviewMetadata.afterRowRemoved({
        'fallbackCandidates': [
          {'lineIndex': 'one'},
        ],
        'fallbackCandidateCount': 1,
        'fallbackAppliedCount': 1,
      }, 0);
      expect(result.containsKey('fallbackCandidates'), isFalse);
      expect(result.containsKey('fallbackCandidateCount'), isFalse);
      expect(result.containsKey('fallbackAppliedCount'), isFalse);
    });

    test('orphan counts without a candidate list are removed', () {
      expect(
        LyricIndexedReviewMetadata.afterRowInserted(const {
          'fallbackCandidateCount': 2,
          'untouched': 'kept',
        }, 0),
        {'untouched': 'kept'},
      );
    });

    test('suggestion records need no remapping after a delete', () {
      final document = _fusedDocument();
      final afterDelete = document.copyWith(
        lines: [...document.lines]..removeAt(0),
        metadata: LyricIndexedReviewMetadata.afterRowRemoved(
          document.metadata,
          0,
        ),
      );
      expect(SecondaryOnlySuggestion.resolve(afterDelete).keys, [0]);
      expect(afterDelete.metadata['secondaryOnlyLineIndices'], [0]);
    });
  });

  group('RecognitionReviewSummary', () {
    test('reports dual-engine counts from metadata', () {
      final document = _fusedDocument(
        extra: {
          'fallbackCandidates': [
            {'lineIndex': 0, 'primaryText': 'a', 'alternativeText': 'b'},
            // Identical texts are not a disagreement.
            {'lineIndex': 2, 'primaryText': 'same', 'alternativeText': 'same'},
            // Out of range rows are ignored.
            {'lineIndex': 9, 'primaryText': 'x', 'alternativeText': 'y'},
          ],
          'segmentationOnlySecondaryCount': 2,
          RecognitionReviewSummary.whisperDecodingKey: {
            'requestedProfile': 'whisper-lyrics-v2',
            'effectiveProfile': 'whisper-lyrics-v2',
          },
        },
      );
      final summary = RecognitionReviewSummary.fromDocument(
        document,
        LyricReviewQueue.build(document),
      );
      expect(summary.hasRecognitionData, isTrue);
      expect(summary.ranTwoEngines, isTrue);
      expect(summary.primaryEngine, 'qwen3-asr-1.7b');
      expect(summary.secondaryEngine, 'whisper.cpp-large-v3');
      expect(summary.totalLines, 3);
      expect(summary.disagreementLines, 1);
      expect(summary.secondaryOnlySuggestions, 1);
      expect(summary.pendingSecondaryOnlySuggestions, 1);
      expect(summary.segmentationOnlySecondary, 2);
      expect(summary.whisperEffectiveProfile, 'whisper-lyrics-v2');
      expect(summary.whisperProfileDegraded, isFalse);
      expect(summary.pendingReview, greaterThanOrEqualTo(1));
    });

    test('missing data stays null instead of becoming zero', () {
      final document = LyricDocument(
        language: 'en',
        lines: [_line('typed by hand', 0, 1000, id: 'a')],
        metadata: const {'generatedBy': 'whisper.cpp'},
      );
      final summary = RecognitionReviewSummary.fromDocument(
        document,
        LyricReviewQueue.build(document),
      );
      expect(summary.hasRecognitionData, isTrue);
      expect(summary.ranTwoEngines, isFalse);
      expect(summary.disagreementLines, isNull);
      expect(summary.secondaryOnlySuggestions, isNull);
      expect(summary.segmentationOnlySecondary, isNull);
      expect(summary.whisperEffectiveProfile, isNull);
    });

    test('imported lyrics have no recognition summary', () {
      final document = LyricDocument(
        language: 'en',
        lines: [_line('imported', 0, 1000, id: 'a')],
      );
      expect(
        RecognitionReviewSummary.fromDocument(
          document,
          LyricReviewQueue.build(document),
        ).hasRecognitionData,
        isFalse,
      );
    });

    test('a degraded Whisper profile is visible', () {
      final document = _fusedDocument(
        extra: {
          RecognitionReviewSummary.whisperDecodingKey: {
            'requestedProfile': 'whisper-lyrics-v2',
            'effectiveProfile': 'whisper-standard-v1',
            'fallbackReason': 'runtime_rejected_arguments: x',
          },
        },
      );
      final summary = RecognitionReviewSummary.fromDocument(
        document,
        LyricReviewQueue.build(document),
      );
      expect(summary.whisperProfileDegraded, isTrue);
      expect(summary.whisperFallbackReason, startsWith('runtime_rejected'));
    });

    test('a kept suggestion is no longer pending', () {
      final reviewed = const LyricReviewDecisionService().setReviewed(
        _fusedDocument(),
        1,
        reviewed: true,
      );
      final summary = RecognitionReviewSummary.fromDocument(
        reviewed,
        LyricReviewQueue.build(reviewed),
      );
      expect(summary.secondaryOnlySuggestions, 1);
      expect(summary.pendingSecondaryOnlySuggestions, 0);
    });
  });
}

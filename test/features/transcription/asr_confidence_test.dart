import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/asr_confidence.dart';

void main() {
  group('scoreAsrLine', () {
    test('a line with no engine score is never presented as a low score', () {
      final score = scoreAsrLine(
        text: '月亮代表我的心',
        start: Duration.zero,
        end: const Duration(seconds: 3),
      );

      expect(score.source, LyricConfidenceSource.unscored);
      expect(score.value, unscoredConfidencePlaceholder);
      expect(
        LyricLine(
          text: '月亮代表我的心',
          startTime: Duration.zero,
          endTime: const Duration(seconds: 3),
          confidence: score.value,
          confidenceSource: score.source,
        ).isLowConfidence(70),
        isFalse,
        reason: '没有分数不等于分数低',
      );
    });

    test('an untouched engine score is reported as a model score', () {
      final score = scoreAsrLine(
        text: '月亮代表我的心',
        start: Duration.zero,
        end: const Duration(seconds: 3),
        explicitConfidence: 88,
      );

      expect(score.source, LyricConfidenceSource.model);
      expect(score.value, 88);
    });

    test('heuristics that lower an engine score are labelled as such', () {
      final score = scoreAsrLine(
        text: '月亮代表我的心',
        start: Duration.zero,
        end: const Duration(seconds: 30),
        explicitConfidence: 88,
      );

      expect(score.source, LyricConfidenceSource.heuristic);
      expect(score.value, lessThan(88));
    });

    test('a suspicious repetition still demotes a real score', () {
      final score = scoreAsrLine(
        text: 'la la la la la la la la',
        start: Duration.zero,
        end: const Duration(seconds: 3),
        explicitConfidence: 90,
      );

      expect(score.source, LyricConfidenceSource.heuristic);
      expect(score.value, lessThanOrEqualTo(55));
    });
  });

  group('scoreWhisperSegment', () {
    test('averages token probabilities into a model score', () {
      final score = scoreWhisperSegment(const {
        'text': 'hello world',
        'tokens': [
          {'text': ' hello', 'p': 0.9},
          {'text': ' world', 'p': 0.7},
        ],
      });

      expect(score.source, LyricConfidenceSource.model);
      expect(score.value, 80);
    });

    test('a segment without token probabilities is unscored, not 50%', () {
      final score = scoreWhisperSegment(const {'text': 'hello world'});

      expect(score.source, LyricConfidenceSource.unscored);
      expect(score.value, unscoredConfidencePlaceholder);
    });

    test('non-speech marker tokens do not count as evidence', () {
      final score = scoreWhisperSegment(const {
        'text': 'hello',
        'tokens': [
          {'text': '[_BEG_]', 'p': 0.1},
          {'text': ' hello', 'p': 0.9},
        ],
      });

      expect(score.source, LyricConfidenceSource.model);
      expect(score.value, 90);
    });

    test('only non-speech markers leaves the segment unscored', () {
      final score = scoreWhisperSegment(const {
        'text': '',
        'tokens': [
          {'text': '[_BEG_]', 'p': 0.1},
        ],
      });

      expect(score.source, LyricConfidenceSource.unscored);
    });
  });

  group('LyricConfidenceSource round trip', () {
    test('json keeps the source', () {
      const line = LyricLine(
        text: '歌词',
        startTime: Duration.zero,
        endTime: Duration(seconds: 2),
        confidence: 50,
        confidenceSource: LyricConfidenceSource.unscored,
      );

      final restored = LyricLine.fromJson(line.toJson());

      expect(restored.confidenceSource, LyricConfidenceSource.unscored);
      expect(restored.hasConfidenceScore, isFalse);
    });

    test('documents written before the field existed stay scored', () {
      final restored = LyricLine.fromJson(const {
        'text': '旧数据行',
        'startTime': 0,
        'endTime': 2000,
        'confidence': 42,
      });

      expect(restored.confidenceSource, LyricConfidenceSource.model);
      expect(restored.isLowConfidence(70), isTrue);
    });

    test('copyWith can promote an unscored line once a human edits it', () {
      const line = LyricLine(
        text: '歌词',
        startTime: Duration.zero,
        endTime: Duration(seconds: 2),
        confidence: 50,
        confidenceSource: LyricConfidenceSource.unscored,
      );

      final edited = line.copyWith(
        confidence: 100,
        confidenceSource: LyricConfidenceSource.model,
      );

      expect(edited.hasConfidenceScore, isTrue);
      expect(edited.isLowConfidence(70), isFalse);
    });
  });
}

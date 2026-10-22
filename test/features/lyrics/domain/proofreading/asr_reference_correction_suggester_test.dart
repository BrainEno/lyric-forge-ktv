import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/reference_lyric_input.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/reference_lyric_line.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/asr_reference_correction_suggester.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

void main() {
  const suggester = AsrReferenceCorrectionSuggester();

  LyricLine asr(String text, int start, int end, {int confidence = 90}) =>
      LyricLine(
        text: text,
        startTime: Duration(milliseconds: start),
        endTime: Duration(milliseconds: end),
        confidence: confidence,
      );

  ReferenceLyricLine ref(String text, {int? start, int? end}) =>
      ReferenceLyricLine(
        text: text,
        startTime: start == null ? null : Duration(milliseconds: start),
        endTime: end == null ? null : Duration(milliseconds: end),
      );

  LyricDocument doc(List<LyricLine> lines) =>
      LyricDocument(language: 'en', lines: lines);

  ReferenceLyricInput input(
    List<ReferenceLyricLine> lines, {
    String? title,
    List<String> warnings = const [],
    List<String> conflicts = const [],
  }) => ReferenceLyricInput(
    lines: lines,
    timed: lines.any((line) => line.hasTimestamp),
    format: 'plain',
    title: title,
    warnings: warnings,
    conflicts: conflicts,
  );

  test('suggests a high-similarity typo without changing draft timing', () {
    final source = asr('Hello word', 2100, 4600);
    final draft = doc([source]);
    final result = suggester.suggest(
      draft: draft,
      reference: input([ref('Hello world', start: 10000, end: 13000)]),
    );

    expect(result.suggestions, hasLength(1));
    final proposal = result.suggestions.single;
    expect(proposal.draftIndex, 0);
    expect(proposal.referenceIndex, 0);
    expect(proposal.currentText, 'Hello word');
    expect(proposal.suggestedText, 'Hello world');
    expect(proposal.alignmentStatus, AsrLineAlignmentStatus.toBeCorrected);
    expect(proposal.similarity, greaterThanOrEqualTo(0.8));
    expect(proposal.referenceHasTimestamp, isTrue);
    expect(proposal.requiresRetiming, isTrue);
    expect(source.startTime, const Duration(milliseconds: 2100));
    expect(source.endTime, const Duration(milliseconds: 4600));
    expect(draft.lines.single.text, 'Hello word');
    expect(result.suggestions.single.currentText, isNot(result.suggestions.single.suggestedText));
  });

  test('keeps low-confidence matches as explicit review suggestions', () {
    final result = suggester.suggest(
      draft: doc([asr('今天天晴', 0, 3000)]),
      reference: input([ref('今天下晴')]),
    );

    expect(result.suggestions, hasLength(1));
    expect(
      result.suggestions.single.alignmentStatus,
      AsrLineAlignmentStatus.lowConfidence,
    );
    expect(
      result.suggestions.single.reasons,
      contains(AsrReferenceCorrectionReason.lowAlignmentConfidence),
    );
    expect(result.suggestions.single.requiresManualReview, isTrue);
  });

  test('does not suggest for identical normalized text', () {
    final result = suggester.suggest(
      draft: doc([asr('Hello, World!', 0, 2000)]),
      reference: input([ref('hello world')]),
    );

    expect(result.suggestions, isEmpty);
  });

  test('never suggests replacing protected draft rows', () {
    final result = suggester.suggest(
      draft: doc([asr('Hello word', 1000, 3000)]),
      reference: input([ref('Hello world')]),
      protectedDraftIndices: const {0},
    );

    expect(result.suggestions, isEmpty);
  });

  test('maps suggestions to original reference indices after header cleanup', () {
    final result = suggester.suggest(
      draft: doc([asr('Hello word', 0, 2000)]),
      reference: input([
        ref('Roadhouse Blues Lyrics'),
        ref('[Verse 1]'),
        ref('Hello world'),
      ], title: 'Roadhouse Blues'),
    );

    expect(result.suggestions, hasLength(1));
    expect(result.suggestions.single.referenceIndex, 2);
    expect(result.removedReferenceLines.map((line) => line.originalIndex), [0, 1]);
  });

  test('does not create suggestions or insert lines for unmatched references', () {
    final result = suggester.suggest(
      draft: doc([asr('First verse', 0, 2000), asr('Last verse', 6000, 8000)]),
      reference: input([
        ref('First verse'),
        ref('Missing middle verse'),
        ref('Last verse'),
      ]),
    );

    expect(result.suggestions, isEmpty);
    expect(result.missingReferenceIndices, [1]);
  });

  test('adds review reason when reference import has warnings or conflicts', () {
    final result = suggester.suggest(
      draft: doc([asr('Hello word', 0, 2000)]),
      reference: input(
        [ref('Hello world')],
        warnings: const ['Timestamp was repaired'],
        conflicts: const ['Duplicate timestamp'],
      ),
    );

    expect(result.suggestions, hasLength(1));
    expect(
      result.suggestions.single.reasons,
      contains(AsrReferenceCorrectionReason.referenceImportWarning),
    );
    expect(result.warnings, ['Duplicate timestamp', 'Timestamp was repaired']);
    expect(result.suggestions.single.requiresManualReview, isTrue);
  });

  test('rejects invalid protected indices and unusable reference text', () {
    expect(
      () => suggester.suggest(
        draft: doc([asr('Hello', 0, 1000)]),
        reference: input([ref('Hello')]),
        protectedDraftIndices: const {-1},
      ),
      throwsArgumentError,
    );
    expect(
      () => suggester.suggest(
        draft: doc([asr('Hello', 0, 1000)]),
        reference: input([ref('[Verse 1]'), ref('Lyrics')]),
      ),
      throwsArgumentError,
    );
  });

  test('exposes immutable suggestions and reason sets', () {
    final result = suggester.suggest(
      draft: doc([asr('Hello word', 0, 2000)]),
      reference: input([ref('Hello world')]),
    );

    expect(() => result.suggestions.add(result.suggestions.single), throwsUnsupportedError);
    expect(
      () => result.suggestions.single.reasons.add(AsrReferenceCorrectionReason.textMismatch),
      throwsUnsupportedError,
    );
  });
}

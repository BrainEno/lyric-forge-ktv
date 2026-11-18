import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/lyric_review_queue.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/recognition_review_summary.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/secondary_only_suggestion.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_review_decision_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/controllers/lyric_editor_document_controller.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_inspector_pane.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_recognition_summary_card.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

const _suggestion = SecondaryOnlySuggestion(
  text: 'every window burning gold',
  startMs: 4000,
  endMs: 7000,
  engine: 'whisper.cpp-large-v3',
  engineConfidence: 88,
);

LyricDocument _document() => LyricDocument(
  language: 'en',
  lines: const [
    LyricLine(
      id: 'a',
      text: 'city lights are calling',
      startTime: Duration.zero,
      endTime: Duration(seconds: 3),
      confidence: 92,
    ),
    LyricLine(
      id: 'b',
      text: 'every window burning gold',
      startTime: Duration(seconds: 4),
      endTime: Duration(seconds: 7),
      confidence: 60,
      confidenceSource: LyricConfidenceSource.heuristic,
    ),
    LyricLine(
      id: 'c',
      text: 'we run until the morning',
      startTime: Duration(seconds: 8),
      endTime: Duration(seconds: 11),
      confidence: 92,
    ),
  ],
  metadata: {
    'qualityMode': 'highestQuality',
    'primaryEngine': 'qwen3-asr-1.7b',
    'fallbackEngine': 'whisper.cpp-large-v3',
    'fallbackStatus': 'completed',
    'fallbackCandidates': [
      {
        'lineIndex': 2,
        'primaryText': 'we run until the morning',
        'alternativeText': 'we ran until the morning',
      },
    ],
    'fallbackCandidateCount': 1,
    'secondaryOnlyLineIndices': [1],
    'secondaryOnlyLineCount': 1,
    SecondaryOnlySuggestion.metadataKey: SecondaryOnlySuggestion.wrap([
      _suggestion,
    ]),
    'whisperDecoding': {
      'requestedProfile': 'whisper-lyrics-v2',
      'effectiveProfile': 'whisper-lyrics-v2',
    },
  },
);

void main() {
  group('controller decisions on a suggestion', () {
    LyricEditorDocumentController controller() {
      var now = DateTime.utc(2026, 11, 14, 12);
      return LyricEditorDocumentController(clock: () => now)..load(_document());
    }

    test('rejecting deletes only that row, keeps other candidates, and is '
        'undoable', () {
      final c = controller();
      c.deleteLine(1);

      final afterDelete = c.document!;
      expect(afterDelete.lines.map((line) => line.text), [
        'city lights are calling',
        'we run until the morning',
      ]);
      expect(SecondaryOnlySuggestion.resolve(afterDelete), isEmpty);
      // The remaining disagreement follows its row instead of vanishing.
      final candidates = afterDelete.metadata['fallbackCandidates'] as List;
      expect((candidates.single as Map)['lineIndex'], 1);
      expect(afterDelete.metadata['secondaryOnlyLineIndices'], isEmpty);
      expect(c.hasChanges, isTrue, reason: 'nothing is saved automatically');

      c.undo();
      expect(c.document!.lines, hasLength(3));
      expect(SecondaryOnlySuggestion.resolve(c.document!).keys, [1]);
      expect(
        (c.document!.metadata['fallbackCandidates'] as List).single,
        containsPair('lineIndex', 2),
      );
    });

    test('keeping records a review decision and leaves the text alone', () {
      final c = controller();
      final result = c.setLineReviewed(1, reviewed: true);

      expect(result.applied, isTrue);
      expect(c.document!.lines[1].text, 'every window burning gold');
      expect(
        const LyricReviewDecisionService().isReviewed(c.document!, 1),
        isTrue,
      );
      expect(LyricReviewQueue.build(c.document!).needsReview(1), isFalse);
      expect(c.hasChanges, isTrue);

      c.undo();
      expect(LyricReviewQueue.build(c.document!).needsReview(1), isTrue);
    });

    test('editing the suggested text turns it into a normal row', () {
      final c = controller();
      c.updateLine(
        1,
        c.document!.lines[1].copyWith(text: 'every window burns with gold'),
      );
      expect(SecondaryOnlySuggestion.resolve(c.document!), isEmpty);
    });
  });

  group('SecondarySuggestionCard', () {
    testWidgets('offers listen, keep and reject', (tester) async {
      var previewed = 0;
      var kept = 0;
      var rejected = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SecondarySuggestionCard(
              suggestion: _suggestion,
              onPreview: () => previewed++,
              onKeep: () => kept++,
              onReject: () => rejected++,
            ),
          ),
        ),
      );

      expect(find.text('建议补入 · 仅 Whisper 识别到'), findsOneWidget);
      await tester.tap(find.text('试听这一行'));
      await tester.tap(find.byKey(const ValueKey('secondary_suggestion_keep')));
      await tester.tap(
        find.byKey(const ValueKey('secondary_suggestion_reject')),
      );
      expect((previewed, kept, rejected), (1, 1, 1));

      for (final key in [
        'secondary_suggestion_keep',
        'secondary_suggestion_reject',
      ]) {
        final size = tester.getSize(find.byKey(ValueKey(key)));
        expect(size.height, greaterThanOrEqualTo(48), reason: key);
      }
    });

    testWidgets('LineInspector shows the card only while pending', (
      tester,
    ) async {
      final line = _document().lines[1];
      final decisions = <bool>[];
      var deleted = 0;
      Widget host({required bool reviewed}) => MaterialApp(
        home: Scaffold(
          body: LineInspector(
            index: 1,
            line: line,
            fallbackCandidate: null,
            secondarySuggestion: _suggestion,
            isReviewed: reviewed,
            onReviewDecision: decisions.add,
            isCurrentPlaybackLine: false,
            isPlaying: false,
            onUpdate: (_) {},
            onDelete: () => deleted++,
            onPreview: () {},
          ),
        ),
      );

      await tester.pumpWidget(host(reviewed: false));
      expect(find.byType(SecondarySuggestionCard), findsOneWidget);
      expect(find.text('建议补入'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('secondary_suggestion_keep')),
      );
      await tester.tap(find.byKey(const ValueKey('secondary_suggestion_keep')));
      await tester.ensureVisible(
        find.byKey(const ValueKey('secondary_suggestion_reject')),
      );
      await tester.tap(
        find.byKey(const ValueKey('secondary_suggestion_reject')),
      );
      expect(decisions, [true]);
      expect(deleted, 1);

      await tester.pumpWidget(host(reviewed: true));
      expect(find.byType(SecondarySuggestionCard), findsNothing);
      expect(find.text('建议补入'), findsNothing);
    });
  });

  group('LyricRecognitionSummaryCard', () {
    Future<void> pump(
      WidgetTester tester,
      RecognitionReviewSummary summary, {
      VoidCallback? onStartReview,
      Size size = const Size(1280, 800),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                LyricRecognitionSummaryCard(
                  summary: summary,
                  onStartReview: onStartReview,
                ),
              ],
            ),
          ),
        ),
      );
    }

    RecognitionReviewSummary summaryFor(LyricDocument document) =>
        RecognitionReviewSummary.fromDocument(
          document,
          LyricReviewQueue.build(document),
        );

    testWidgets('shows counts and starts the review queue', (tester) async {
      var started = 0;
      final summary = summaryFor(_document());
      await pump(tester, summary, onStartReview: () => started++);

      expect(find.text('识别结果 · Qwen3-ASR + Whisper 双引擎'), findsOneWidget);
      expect(
        find.textContaining('双引擎分歧：1', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('建议补入：1', findRichText: true), findsOneWidget);
      expect(find.textContaining('总行数：3', findRichText: true), findsOneWidget);
      expect(find.textContaining('%', findRichText: true), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('lyric_recognition_summary_start')),
      );
      expect(started, 1);
      expect(
        tester
            .getSize(
              find.byKey(const ValueKey('lyric_recognition_summary_start')),
            )
            .height,
        greaterThanOrEqualTo(48),
      );

      // Details, including the Whisper profile, are one tap away.
      expect(find.textContaining('歌词增强'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('lyric_recognition_summary_toggle')),
      );
      await tester.pump();
      expect(find.textContaining('Whisper 参数：歌词增强'), findsOneWidget);
    });

    testWidgets('single-engine runs say unavailable, not zero', (tester) async {
      final document = LyricDocument(
        language: 'en',
        lines: const [
          LyricLine(
            id: 'a',
            text: 'only line',
            startTime: Duration.zero,
            endTime: Duration(seconds: 2),
            confidence: 95,
          ),
        ],
        metadata: const {'generatedBy': 'whisper.cpp'},
      );
      await pump(tester, summaryFor(document));

      expect(
        find.textContaining('双引擎分歧：不可用', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('建议补入：不可用', findRichText: true),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('lyric_recognition_summary_toggle')),
      );
      await tester.pump();
      expect(find.textContaining('Whisper 参数：未采集'), findsOneWidget);
    });

    testWidgets('a profile fallback is explained', (tester) async {
      final base = _document();
      final document = base.copyWith(
        metadata: {
          ...base.metadata,
          'whisperDecoding': {
            'requestedProfile': 'whisper-lyrics-v2',
            'effectiveProfile': 'whisper-standard-v1',
          },
        },
      );
      await pump(tester, summaryFor(document));
      await tester.tap(
        find.byKey(const ValueKey('lyric_recognition_summary_toggle')),
      );
      await tester.pump();
      expect(find.textContaining('已安全回退'), findsOneWidget);
    });

    testWidgets('fits a compact phone width without overflow', (tester) async {
      await pump(
        tester,
        summaryFor(_document()),
        onStartReview: () {},
        size: const Size(360, 720),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('复核'), findsOneWidget);
    });
  });
}

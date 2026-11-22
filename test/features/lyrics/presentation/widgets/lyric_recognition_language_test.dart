import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/lyric_review_queue.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/recognition_review_summary.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_recognition_summary_card.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/spoken_language.dart';

// Every lyric below is synthetic text written for these tests.

LyricLine _line(int index) => LyricLine(
  text: '第 $index 句',
  startTime: Duration(seconds: index * 5),
  endTime: Duration(seconds: index * 5 + 4),
  id: 'l$index',
);

LyricDocument _document({
  int lines = 12,
  String language = 'en',
  Map<String, Object?>? spoken,
  bool recognized = true,
}) => LyricDocument(
  language: language,
  lines: [for (var index = 0; index < lines; index++) _line(index)],
  metadata: {
    if (recognized) 'primaryEngine': 'whisper-large-v3',
    'spokenLanguage': ?spoken,
  },
);

RecognitionReviewSummary _summary(LyricDocument document) =>
    RecognitionReviewSummary.fromDocument(
      document,
      LyricReviewQueue.build(document),
    );

Future<void> _pumpCard(
  WidgetTester tester,
  RecognitionReviewSummary summary, {
  VoidCallback? onBack,
}) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: LyricRecognitionSummaryCard(
            summary: summary,
            onStartReview: null,
            onBackToProject: onBack,
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('RecognitionReviewSummary language (D-062)', () {
    test('reads the recognition\'s language record', () {
      final summary = _summary(
        _document(
          spoken: const SpokenLanguageResolution(
            language: 'en',
            source: SpokenLanguageSource.detected,
          ).toJson(),
        ),
      );
      expect(summary.sungLanguage, 'en');
      expect(summary.sungLanguageSource, 'detected');
      expect(summary.recognizedLanguage, 'en');
      expect(summary.sungLanguageLine, '英文（自动判断）');
      expect(summary.looksFailed, isFalse);
    });

    test('a song setting and an unresolved run read as such', () {
      expect(
        _summary(
          _document(
            spoken: const SpokenLanguageResolution(
              language: 'ja',
              source: SpokenLanguageSource.project,
            ).toJson(),
          ),
        ).sungLanguageLine,
        '日文（本首歌设置）',
      );
      final unresolved = _summary(
        _document(
          spoken: const SpokenLanguageResolution.unresolved().toJson(),
        ),
      );
      expect(unresolved.sungLanguage, isNull);
      expect(unresolved.sungLanguageLine, isNull);
      expect(_summary(_document()).sungLanguageLine, isNull);
    });

    test('a two-row draft looks failed', () {
      final summary = _summary(_document(lines: 2));
      expect(summary.looksFailed, isTrue);
      expect(summary.languageLooksMisdetected, isFalse);
      expect(
        LyricRecognitionSummaryCard.failureHint(summary),
        allOf(contains('整首只识别出 2 行'), contains('演唱语言')),
      );
    });

    test('Norwegian nobody chose looks failed, even with rows', () {
      final summary = _summary(_document(language: 'nn'));
      expect(summary.languageLooksMisdetected, isTrue);
      expect(summary.looksFailed, isTrue);
      expect(
        LyricRecognitionSummaryCard.failureHint(summary),
        contains('识别按挪威语处理了这首歌'),
      );
      // Set on purpose for this song: believed.
      final chosen = _summary(
        _document(
          language: 'nn',
          spoken: const SpokenLanguageResolution(
            language: 'nn',
            source: SpokenLanguageSource.project,
          ).toJson(),
        ),
      );
      expect(chosen.looksFailed, isFalse);
    });

    test('a full draft or hand-typed lyrics look fine', () {
      expect(_summary(_document()).looksFailed, isFalse);
      expect(
        _summary(_document(lines: 1, recognized: false)).looksFailed,
        isFalse,
      );
      expect(
        LyricRecognitionSummaryCard.failureHint(_summary(_document())),
        isNull,
      );
    });

    test('its list of made-up languages is the recognition\'s', () {
      expect(
        RecognitionReviewSummary.misdetectedLanguages,
        SpokenLanguagePolicy.hallucinationProne,
      );
      for (final code in SpokenLanguagePolicy.selectableLanguages) {
        expect(
          RecognitionReviewSummary.languageLabel(code),
          SpokenLanguagePolicy.label(code),
          reason: code,
        );
      }
    });
  });

  group('summary card', () {
    testWidgets('a failed draft says what to do and leads back', (
      tester,
    ) async {
      var back = 0;
      await _pumpCard(
        tester,
        _summary(_document(lines: 2)),
        onBack: () => back++,
      );

      expect(
        find.byKey(const ValueKey('lyric_recognition_summary_failed')),
        findsOneWidget,
      );
      expect(find.textContaining('整首只识别出 2 行'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('lyric_recognition_summary_back')),
      );
      expect(back, 1);
    });

    testWidgets('without a way back the notice has no button', (tester) async {
      await _pumpCard(tester, _summary(_document(lines: 1)));
      expect(
        find.byKey(const ValueKey('lyric_recognition_summary_failed')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('lyric_recognition_summary_back')),
        findsNothing,
      );
    });

    testWidgets('a good draft has no notice; expanding shows the language', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        _summary(
          _document(
            spoken: const SpokenLanguageResolution(
              language: 'en',
              source: SpokenLanguageSource.songInfo,
            ).toJson(),
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('lyric_recognition_summary_failed')),
        findsNothing,
      );
      expect(find.textContaining('演唱语言：'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('lyric_recognition_summary_toggle')),
      );
      await tester.pump();
      expect(find.textContaining('演唱语言：英文（按歌名判断）'), findsOneWidget);
    });
  });
}

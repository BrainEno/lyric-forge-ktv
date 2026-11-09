import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_inspector_pane.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

void main() {
  testWidgets('confidence 100 shows alternative until explicitly reviewed', (
    tester,
  ) async {
    LyricLine? updated;
    const line = LyricLine(
      id: 'line-1',
      text: 'primary',
      confidence: 100,
      startTime: Duration.zero,
      endTime: Duration(seconds: 2),
    );
    Widget host({required bool reviewed}) => MaterialApp(
      home: Scaffold(
        body: LineInspector(
          index: 0,
          line: line,
          fallbackCandidate: const {
            'primaryEngine': 'qwen',
            'alternativeEngine': 'whisper',
            'primaryText': 'primary',
            'alternativeText': 'alternative',
          },
          isReviewed: reviewed,
          onReviewDecision: (_) {},
          isCurrentPlaybackLine: false,
          isPlaying: false,
          onUpdate: (value) => updated = value,
          onDelete: () {},
          onPreview: () {},
        ),
      ),
    );
    await tester.pumpWidget(host(reviewed: false));
    expect(find.text('alternative', findRichText: true), findsOneWidget);
    expect(find.text('采用备选'), findsOneWidget);
    await tester.ensureVisible(find.text('采用备选'));
    await tester.tap(find.text('采用备选'));
    await tester.pump();
    expect(updated?.text, 'alternative');
    expect(find.text('采用备选'), findsOneWidget);
    await tester.pumpWidget(host(reviewed: true));
    expect(find.text('采用备选'), findsNothing);
    expect(find.text('取消已复核标记'), findsOneWidget);
    await tester.pumpWidget(host(reviewed: false));
    expect(find.text('采用备选'), findsOneWidget);
  });

  testWidgets('compares model originals and can restore primary after fusion', (
    tester,
  ) async {
    LyricLine? updated;
    const current = LyricLine(
      id: 'line-1',
      text: '月光🌙',
      confidence: 76,
      isChorus: true,
      startTime: Duration(milliseconds: 1200),
      endTime: Duration(milliseconds: 3300),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LineInspector(
            index: 0,
            line: current,
            fallbackCandidate: const {
              'primaryEngine': 'whisper',
              'alternativeEngine': 'qwen',
              'primaryText': '月亮🌙',
              'alternativeText': '月光🌙',
              'selected': 'qwen',
            },
            isReviewed: false,
            onReviewDecision: (_) {},
            isCurrentPlaybackLine: false,
            isPlaying: false,
            onUpdate: (line) => updated = line,
            onDelete: () {},
            onPreview: () {},
          ),
        ),
      ),
    );
    expect(updated, isNull);
    expect(find.text('Whisper 原始识别'), findsOneWidget);
    expect(find.text('Qwen 备选'), findsOneWidget);
    expect(find.text('当前结果来自 Whisper'), findsNothing);
    final primary = tester.widget<Text>(
      find.byKey(const ValueKey('primary_candidate_text')),
    );
    final alternative = tester.widget<Text>(
      find.byKey(const ValueKey('alternative_candidate_text')),
    );
    expect(primary.textSpan!.toPlainText(), '月亮🌙');
    expect(alternative.textSpan!.toPlainText(), '月光🌙');
    final spans = (primary.textSpan! as TextSpan).children!.cast<TextSpan>();
    expect(
      spans.any(
        (span) =>
            span.text == '亮' &&
            span.style?.decoration == TextDecoration.underline,
      ),
      isTrue,
    );
    await tester.ensureVisible(find.text('采用主模型原文'));
    await tester.tap(find.text('采用主模型原文'));
    await tester.pump();
    expect(updated?.text, '月亮🌙');
    expect(updated?.startTime, current.startTime);
    expect(updated?.endTime, current.endTime);
    expect(updated?.id, current.id);
    expect(updated?.isChorus, isTrue);
    await tester.ensureVisible(find.text('采用备选'));
    await tester.tap(find.text('采用备选'));
    await tester.pump();
    expect(updated?.text, '月光🌙');
    expect(updated?.startTime, current.startTime);
    expect(updated?.endTime, current.endTime);
  });

  testWidgets('without original evidence compares against edited text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LineInspector(
            index: 0,
            line: const LyricLine(
              text: '初始歌词',
              startTime: Duration.zero,
              endTime: Duration(seconds: 1),
            ),
            fallbackCandidate: const {'alternativeText': '新的歌词'},
            isReviewed: false,
            onReviewDecision: (_) {},
            isCurrentPlaybackLine: false,
            isPlaying: false,
            onUpdate: (_) {},
            onDelete: () {},
            onPreview: () {},
          ),
        ),
      ),
    );
    expect(find.text('当前歌词'), findsOneWidget);
    expect(find.text('备用引擎 备选'), findsOneWidget);
    expect(find.text('采用主模型原文'), findsNothing);
    await tester.enterText(find.byType(TextField), '人工编辑');
    await tester.pump();
    final text = tester.widget<Text>(
      find.byKey(const ValueKey('primary_candidate_text')),
    );
    expect(text.textSpan!.toPlainText(), '人工编辑');
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not offer primary-only Whisper as an alternative', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LineInspector(
            index: 0,
            line: const LyricLine(
              text: 'original',
              startTime: Duration.zero,
              endTime: Duration(seconds: 1),
            ),
            fallbackCandidate: const {
              'primaryEngine': 'whisper',
              'whisperText': 'original',
            },
            isReviewed: false,
            onReviewDecision: (_) {},
            isCurrentPlaybackLine: false,
            isPlaying: false,
            onUpdate: (_) {},
            onDelete: () {},
            onPreview: () {},
          ),
        ),
      ),
    );
    expect(find.text('采用备选'), findsNothing);
    expect(
      find.byKey(const ValueKey('alternative_candidate_text')),
      findsNothing,
    );
  });

  testWidgets('legacy Qwen and Whisper evidence remains selectable', (
    tester,
  ) async {
    LyricLine? updated;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LineInspector(
            index: 0,
            line: const LyricLine(
              text: '备用',
              startTime: Duration.zero,
              endTime: Duration(seconds: 1),
            ),
            fallbackCandidate: const {'qwenText': '原文', 'whisperText': '备用'},
            isReviewed: false,
            onReviewDecision: (_) {},
            isCurrentPlaybackLine: false,
            isPlaying: false,
            onUpdate: (line) => updated = line,
            onDelete: () {},
            onPreview: () {},
          ),
        ),
      ),
    );
    expect(find.text('Qwen 原始识别'), findsOneWidget);
    expect(find.text('Whisper 备选'), findsOneWidget);
    await tester.ensureVisible(find.text('采用主模型原文'));
    await tester.tap(find.text('采用主模型原文'));
    expect(updated?.text, '原文');
  });
}

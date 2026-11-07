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
    expect(find.text('alternative'), findsOneWidget);
    expect(find.text('采用备选'), findsOneWidget);
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
}

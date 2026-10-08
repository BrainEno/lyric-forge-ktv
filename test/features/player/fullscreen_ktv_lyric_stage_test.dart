import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/fullscreen_ktv_lyric_stage.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

void main() {
  const document = LyricDocument(
    language: 'en',
    globalOffset: Duration(milliseconds: 500),
    lines: [
      LyricLine(
        text: 'First line',
        startTime: Duration.zero,
        endTime: Duration(seconds: 2),
      ),
      LyricLine(
        text: 'Second line',
        startTime: Duration(seconds: 2),
        endTime: Duration(seconds: 4),
      ),
      LyricLine(
        text: 'Third line',
        startTime: Duration(seconds: 4),
        endTime: Duration(seconds: 6),
      ),
    ],
  );

  test('current lyric index respects global offset', () {
    expect(
      fullscreenKtvCurrentLyricIndex(
        document,
        const Duration(milliseconds: 2499),
      ),
      0,
    );
    expect(
      fullscreenKtvCurrentLyricIndex(
        document,
        const Duration(milliseconds: 2500),
      ),
      1,
    );
  });

  testWidgets('stage focuses current line and keeps neighbours visible',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FullscreenKtvLyricStage(
            document: document,
            position: Duration(seconds: 3),
          ),
        ),
      ),
    );

    expect(find.text('First line'), findsOneWidget);
    expect(find.text('Second line'), findsOneWidget);
    expect(find.text('Third line'), findsOneWidget);

    final current = tester.widget<Text>(
      find.byKey(const ValueKey('current:2000')),
    );
    final previous = tester.widget<Text>(
      find.byKey(const ValueKey('previous:0')),
    );
    expect(current.style?.fontWeight, FontWeight.w900);
    expect(current.style?.color, Colors.white);
    expect(previous.style?.fontWeight, FontWeight.w500);
  });

  testWidgets('extra-large view keeps lyric measure bounded', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FullscreenKtvLyricStage(
            document: document,
            position: Duration(seconds: 3),
          ),
        ),
      ),
    );

    final frame = tester.widget<ConstrainedBox>(
      find.byKey(const ValueKey('fullscreen-ktv-lyric-stage-frame')),
    );
    expect(frame.constraints.maxWidth, 1480);
  });

  testWidgets('empty document exposes a readable empty state', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FullscreenKtvLyricStage(
            document: LyricDocument(language: 'en', lines: []),
            position: Duration.zero,
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('fullscreen-ktv-empty-lyrics')),
      findsOneWidget,
    );
    expect(find.text('当前歌曲没有可用歌词'), findsOneWidget);
  });
}

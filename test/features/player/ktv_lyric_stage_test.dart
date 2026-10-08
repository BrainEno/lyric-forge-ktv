import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/ktv_lyric_stage.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

void main() {
  const lyrics = <LyricLine>[
    LyricLine(
      text: 'Previous line',
      startTime: Duration.zero,
      endTime: Duration(seconds: 2),
    ),
    LyricLine(
      text: 'Current line',
      startTime: Duration(seconds: 2),
      endTime: Duration(seconds: 4),
    ),
    LyricLine(
      text: 'Next line',
      startTime: Duration(seconds: 4),
      endTime: Duration(seconds: 6),
    ),
  ];

  Future<void> pumpStage(
    WidgetTester tester, {
    required Size size,
    int? currentIndex = 1,
    List<LyricLine> source = lyrics,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: KtvLyricStage(
            lyrics: source,
            currentIndex: currentIndex,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('focuses current lyric and bounds extra-wide content',
      (tester) async {
    await pumpStage(tester, size: const Size(1920, 1080));

    expect(find.text('Previous line'), findsOneWidget);
    expect(find.text('Current line'), findsOneWidget);
    expect(find.text('Next line'), findsOneWidget);

    final currentText = tester.widget<Text>(find.text('Current line'));
    final previousText = tester.widget<Text>(find.text('Previous line'));
    expect(currentText.style?.fontWeight, FontWeight.w900);
    expect(previousText.style?.fontWeight, FontWeight.w500);

    final bounds = tester.getSize(
      find.byKey(const ValueKey('ktv-lyric-stage-bounds')),
    );
    expect(bounds.width, lessThanOrEqualTo(1440));
    expect(tester.takeException(), isNull);
  });

  testWidgets('short landscape viewport keeps focused lyrics reachable',
      (tester) async {
    await pumpStage(tester, size: const Size(844, 390));

    expect(
      find.byKey(const ValueKey('ktv-lyric-current')),
      findsOneWidget,
    );
    final currentText = tester.widget<Text>(find.text('Current line'));
    expect(currentText.maxLines, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('animates to the next focused lyric', (tester) async {
    await pumpStage(tester, size: const Size(1366, 768));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: const Scaffold(
          body: KtvLyricStage(
            lyrics: lyrics,
            currentIndex: 2,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    final currentSlot = find.byKey(const ValueKey('ktv-lyric-current'));
    expect(
      find.descendant(of: currentSlot, matching: find.text('Next line')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows an explicit empty state', (tester) async {
    await pumpStage(
      tester,
      size: const Size(390, 844),
      source: const <LyricLine>[],
      currentIndex: null,
    );

    expect(
      find.byKey(const ValueKey('ktv-lyric-stage-empty')),
      findsOneWidget,
    );
    expect(find.text('当前歌曲没有可用歌词'), findsOneWidget);
  });
}

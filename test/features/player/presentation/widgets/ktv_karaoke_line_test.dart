import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/theme/color_tokens.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/ktv_karaoke_line.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

const _fourSeconds = LyricLine(
  text: '你好世界',
  startTime: Duration.zero,
  endTime: Duration(seconds: 4),
);

List<double> _sung(
  LyricLine line,
  int milliseconds, {
  Duration offset = Duration.zero,
  Duration? fallbackEnd,
}) {
  final units = ktvSungUnits(
    line,
    Duration(milliseconds: milliseconds),
    offset: offset,
    fallbackEnd: fallbackEnd,
  );
  return [for (final unit in units) unit.sung];
}

List<Color?> _spanColors(WidgetTester tester) {
  final text = tester.widget<Text>(find.byKey(const ValueKey('line')));
  return [
    for (final span in (text.textSpan! as TextSpan).children!)
      (span as TextSpan).style?.color,
  ];
}

Widget _host(Widget child) {
  return MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('ktvSungUnits', () {
    test('spreads a row without word timing evenly over its characters', () {
      expect(_sung(_fourSeconds, 0), [0, 0, 0, 0]);
      expect(_sung(_fourSeconds, 1500), [1, 0.5, 0, 0]);
      expect(_sung(_fourSeconds, 4000), [1, 1, 1, 1]);
    });

    test('weights Latin words by syllables and keeps their spaces', () {
      const line = LyricLine(
        text: 'Hello world',
        startTime: Duration.zero,
        endTime: Duration(seconds: 3),
      );
      final units = ktvSungUnits(line, const Duration(milliseconds: 2500));
      expect([for (final unit in units) unit.text], ['Hello ', 'world']);
      expect([for (final unit in units) unit.sung], [1, 0.5]);
    });

    test('follows real word timing when the row has it', () {
      const line = LyricLine(
        text: '你好世界',
        startTime: Duration.zero,
        endTime: Duration(seconds: 4),
        words: [
          LyricWordTiming(text: '你', start: Duration.zero, end: _ms500),
          LyricWordTiming(text: '好', start: _ms500, end: _ms2000),
          LyricWordTiming(text: '世界', start: _ms2000, end: _ms4000),
        ],
      );
      // 好 is sung from 0.5 s to 2 s, so it is half done at 1.25 s.
      expect(_sung(line, 1250), [1, 0.5, 0, 0]);
    });

    test('applies the document offset', () {
      expect(
        _sung(_fourSeconds, 2000, offset: const Duration(milliseconds: 500)),
        [1, 0.5, 0, 0],
      );
    });

    test('closes a row without an end at the next row', () {
      const open = LyricLine(
        text: '你好',
        startTime: Duration.zero,
        endTime: Duration.zero,
      );
      expect(_sung(open, 1500, fallbackEnd: const Duration(seconds: 2)), [
        1,
        0.5,
      ]);
      expect(_sung(open, 1), [1, 1], reason: 'no end at all: sung at once');
    });
  });

  testWidgets('colours sung characters and blends the one being sung', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const KtvKaraokeLine(
          textKey: ValueKey('line'),
          line: _fourSeconds,
          position: Duration(milliseconds: 1500),
          style: TextStyle(color: AppColors.pureWhite),
          maxLines: 2,
        ),
      ),
    );

    expect(find.text('你好世界'), findsOneWidget);
    expect(_spanColors(tester), [
      AppColors.accent,
      Color.lerp(AppColors.pureWhite, AppColors.accent, 0.5),
      AppColors.pureWhite,
      AppColors.pureWhite,
    ]);
  });

  testWidgets('keeps the colour moving between position updates', (
    tester,
  ) async {
    Widget line(Duration position, {bool playing = true}) => _host(
      KtvKaraokeLine(
        textKey: const ValueKey('line'),
        line: _fourSeconds,
        position: position,
        isPlaying: playing,
        style: const TextStyle(color: AppColors.pureWhite),
        maxLines: 2,
      ),
    );

    await tester.pumpWidget(line(const Duration(milliseconds: 1000)));
    // First tick: the ticker's clock starts here.
    await tester.pump();
    expect(_spanColors(tester)[1], AppColors.pureWhite);

    await tester.pump(const Duration(milliseconds: 250));
    expect(
      _spanColors(tester)[1],
      Color.lerp(AppColors.pureWhite, AppColors.accent, 0.25),
    );

    // The estimate never runs more than 400 ms past the last report.
    await tester.pump(const Duration(seconds: 2));
    expect(
      _spanColors(tester)[1],
      Color.lerp(AppColors.pureWhite, AppColors.accent, 0.4),
    );

    // Paused: the reported position is shown as is.
    await tester.pumpWidget(
      line(const Duration(milliseconds: 1000), playing: false),
    );
    expect(_spanColors(tester)[1], AppColors.pureWhite);
  });
}

const _ms500 = Duration(milliseconds: 500);
const _ms2000 = Duration(seconds: 2);
const _ms4000 = Duration(seconds: 4);

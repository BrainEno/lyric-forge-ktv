import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_tap_sync_prompt_card.dart';

Future<void> _pump(WidgetTester tester, LyricTapSyncPromptCard card) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: card)));

void main() {
  testWidgets('untimed lyrics with audio offer 开始打轴', (tester) async {
    var opened = 0;
    await _pump(
      tester,
      LyricTapSyncPromptCard(
        lineCount: 12,
        hasAudio: true,
        onStartTapSync: () => opened++,
      ),
    );

    expect(find.text('歌词还没有时间轴'), findsOneWidget);
    expect(find.textContaining('12 行'), findsOneWidget);
    await tester.tap(find.byKey(LyricTapSyncPromptCard.startKey));
    expect(opened, 1);
  });

  testWidgets('without audio the button waits for a recording', (tester) async {
    var opened = 0;
    await _pump(
      tester,
      LyricTapSyncPromptCard(
        lineCount: 3,
        hasAudio: false,
        onStartTapSync: () => opened++,
      ),
    );

    expect(find.textContaining('还没有音频'), findsOneWidget);
    final button = tester.widget<ButtonStyleButton>(
      find.byKey(LyricTapSyncPromptCard.startKey),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('no tool available disables the button', (tester) async {
    await _pump(
      tester,
      const LyricTapSyncPromptCard(
        lineCount: 3,
        hasAudio: true,
        onStartTapSync: null,
      ),
    );
    final button = tester.widget<ButtonStyleButton>(
      find.byKey(LyricTapSyncPromptCard.startKey),
    );
    expect(button.onPressed, isNull);
  });
}

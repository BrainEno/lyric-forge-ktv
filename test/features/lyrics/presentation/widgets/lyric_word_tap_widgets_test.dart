import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_batch_text_edit.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_proofread_menu_button.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_tap_controls.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_tap_sync_dialog.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_word_tap_dialog.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_word_timing_strip.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_state.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

// Every lyric below is synthetic text written for these tests.
Duration _ms(int value) => Duration(milliseconds: value);

LyricLine _line(String text, int startMs, int endMs, {String? id}) => LyricLine(
  text: text,
  startTime: _ms(startMs),
  endTime: _ms(endMs),
  id: id,
);

class _FakePlayer {
  final StreamController<PlaybackState> _states =
      StreamController<PlaybackState>.broadcast();
  PlaybackState state = const PlaybackState.idle();
  final List<Duration> seeks = [];
  Duration now = Duration.zero;

  void report(PlaybackState next) {
    state = next;
    _states.add(next);
  }

  void at(int ms) => report(state.copyWith(isPlaying: true, position: _ms(ms)));

  LyricTapSyncTransport get transport => LyricTapSyncTransport(
    currentState: () => state,
    states: _states.stream,
    play: () async => report(state.copyWith(isPlaying: true)),
    pause: () async => report(state.copyWith(isPlaying: false)),
    seek: (position) async {
      seeks.add(position);
      report(state.copyWith(position: position));
    },
  );
}

Future<(LyricBatchTextEdit? Function(), _FakePlayer)> _open(
  WidgetTester tester,
  LyricDocument document, {
  int startIndex = 0,
}) async {
  final player = _FakePlayer();
  LyricBatchTextEdit? result;
  tester.view.physicalSize = const Size(1200, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async => result = await showDialog(
                context: context,
                builder: (_) => LyricWordTapDialog(
                  document: document,
                  startIndex: startIndex,
                  transport: player.transport,
                  now: () => player.now,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return (() => result, player);
}

void main() {
  final song = LyricDocument(
    language: 'zh',
    lines: [
      _line('我爱你', 5000, 7000, id: 'a'),
      _line('Hold me', 8000, 10000, id: 'b'),
    ],
  );

  Future<void> space(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
  }

  Future<void> pressAt(WidgetTester tester, _FakePlayer player, int ms) async {
    player.at(ms);
    await tester.pump();
    await space(tester);
  }

  String progress(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey('word_tap_progress')))
      .data!;

  group('LyricWordTapDialog', () {
    testWidgets('times every character and applies word timing', (
      tester,
    ) async {
      final (result, player) = await _open(tester, song);
      // Paused on open: two seconds before the first row.
      expect(player.seeks, [_ms(3000)]);
      expect(find.text('开始播放（空格）'), findsOneWidget);
      await space(tester);
      expect(player.state.isPlaying, isTrue);
      expect(find.text('唱到「我」时按下（空格）'), findsOneWidget);

      await pressAt(tester, player, 5000);
      await pressAt(tester, player, 5400);
      expect(find.text('唱到「你」时按下（空格）'), findsOneWidget);
      expect(find.text('还没有按完一行'), findsOneWidget);
      await pressAt(tester, player, 5800);
      expect(progress(tester), '已完成 1 行 · 共 2 行');
      expect(find.text('唱到「Hold」时按下（空格）'), findsOneWidget);

      await pressAt(tester, player, 6500);
      expect(find.text('应用 1 行'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('word_tap_confirm')));
      await tester.pumpAndSettle();
      final edit = result()!;
      final line = edit.document.lines.first;
      expect(
        [
          for (final w in line.words)
            (w.text, w.start.inMilliseconds, w.end.inMilliseconds),
        ],
        [('我', 5000, 5400), ('爱', 5400, 5800), ('你', 5800, 6500)],
      );
      expect(line.startTime, _ms(5000));
      expect(edit.document.lines[1].words, isEmpty);
      expect(
        edit.message,
        '${LyricWordTapStrings.applied(1)} ${LyricWordTapStrings.partial(2)}',
      );
      expect(edit.selectedLineIndex, 0);
    });

    testWidgets('redo row drops its presses and seeks before it', (
      tester,
    ) async {
      final (_, player) = await _open(tester, song);
      await space(tester);
      await pressAt(tester, player, 5000);
      await pressAt(tester, player, 5400);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.pump();
      expect(find.text('唱到「我」时按下（空格）'), findsOneWidget);
      expect(player.seeks.last, _ms(3000));

      await pressAt(tester, player, 5100);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(find.text('唱到「我」时按下（空格）'), findsOneWidget);
    });

    testWidgets('a row of silence only has nothing to time', (tester) async {
      await _open(
        tester,
        LyricDocument(language: 'zh', lines: [_line('♪', 0, 1000)]),
      );
      expect(find.text('从选中行往后没有可演唱的文字。'), findsOneWidget);
      expect(find.text('没有可打轴的行'), findsOneWidget);
    });
  });

  test('the tap clock extrapolates and removes the offset and latency', () {
    var now = Duration.zero;
    final clock = LyricTapClock(
      initial: const PlaybackState.idle(),
      offset: _ms(500),
      now: () => now,
    );
    clock.report(
      const PlaybackState.idle().copyWith(
        isPlaying: true,
        position: _ms(10000),
      ),
    );
    now = _ms(200);
    expect(clock.audioNow(), _ms(10200));
    expect(clock.pressTime(latencyMs: 80), _ms(9620));
    now = _ms(5000);
    expect(clock.audioNow(), _ms(10600));
    expect(clock.toAudio(_ms(-900)), Duration.zero);
    expect(clock.toTimeline(_ms(300)), Duration.zero);
  });

  testWidgets('the proofread menu offers word tap-to-sync', (tester) async {
    var fired = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: LyricProofreadMenuButton(onWordTap: () => fired++)),
        ),
      ),
    );
    await tester.tap(find.text(LyricProofreadMenuButton.label));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(LyricWordTapStrings.actionTitle));
    await tester.pumpAndSettle();
    await tester.tap(find.text(LyricWordTapStrings.actionTitle));
    await tester.pumpAndSettle();
    expect(fired, 1);
  });

  testWidgets('word chips seek and the strip can clear word timing', (
    tester,
  ) async {
    final seeks = <Duration>[];
    var cleared = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LyricWordTimingStrip(
            line: LyricLine(
              text: '我爱',
              startTime: _ms(1000),
              endTime: _ms(2000),
              words: [
                LyricWordTiming(text: '我', start: _ms(1000), end: _ms(1500)),
                LyricWordTiming(text: '爱', start: _ms(1500), end: _ms(2000)),
              ],
            ),
            onSeek: seeks.add,
            onClear: () => cleared++,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('word_timing_1')));
    expect(seeks, [_ms(1500)]);
    await tester.tap(find.byKey(const ValueKey('word_timing_clear')));
    expect(cleared, 1);
  });
}

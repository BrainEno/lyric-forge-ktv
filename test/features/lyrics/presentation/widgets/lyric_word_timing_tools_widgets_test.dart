import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_draft_health_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_batch_text_edit.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_proofread_menu_button.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_recognition_summary_card.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_tap_sync_dialog.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_word_timing_check_dialog.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_word_timing_edit_dialog.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_word_timing_strip.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_state.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

// Every lyric below is synthetic text written for these tests.
Duration _ms(int value) => Duration(milliseconds: value);

LyricWordTiming _w(String text, int start, int end) =>
    LyricWordTiming(text: text, start: _ms(start), end: _ms(end));

List<(String, int, int)> _times(LyricLine line) => [
  for (final word in line.words)
    (word.text, word.start.inMilliseconds, word.end.inMilliseconds),
];

class _FakePlayer {
  final StreamController<PlaybackState> _states =
      StreamController<PlaybackState>.broadcast();
  PlaybackState state = const PlaybackState.idle();
  final List<Duration> seeks = [];
  int pauses = 0;

  void report(PlaybackState next) {
    state = next;
    _states.add(next);
  }

  LyricTapSyncTransport get transport => LyricTapSyncTransport(
    currentState: () => state,
    states: _states.stream,
    play: () async => report(state.copyWith(isPlaying: true)),
    pause: () async {
      pauses++;
      report(state.copyWith(isPlaying: false));
    },
    seek: (position) async {
      seeks.add(position);
      report(state.copyWith(position: position));
    },
  );
}

Future<LyricBatchTextEdit? Function()> _open(
  WidgetTester tester,
  Widget Function() dialog,
) async {
  LyricBatchTextEdit? result;
  tester.view.physicalSize = const Size(1200, 2000);
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
                builder: (_) => dialog(),
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
  return () => result;
}

void main() {
  group('LyricWordTimingCheckDialog', () {
    final document = LyricDocument(
      language: 'zh',
      lines: [
        LyricLine(
          text: '我爱你们',
          startTime: _ms(0),
          endTime: _ms(1000),
          words: [_w('我', 0, 300), _w('爱', 300, 600), _w('你', 600, 1000)],
        ),
        LyricLine(
          text: '啊呀',
          startTime: _ms(2000),
          endTime: _ms(5100),
          words: [_w('啊', 2000, 5000), _w('呀', 5000, 5100)],
        ),
        LyricLine(text: '没有', startTime: _ms(6000), endTime: _ms(7000)),
      ],
    );

    testWidgets('lists findings, selects fixes and clears stale words', (
      tester,
    ) async {
      final previewed = <int>[];
      final result = await _open(
        tester,
        () => LyricWordTimingCheckDialog(
          document: document,
          onPreviewLine: previewed.add,
        ),
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('word_check_coverage')))
            .data,
        '1 行有可用的逐字时间，2 行导出时按字数估算（共 3 行有演唱文字）。',
      );
      expect(find.text('失效 1 行，拖长 1 行'), findsOneWidget);
      expect(find.textContaining('「啊」拖了 3.0 秒'), findsOneWidget);
      expect(find.text('整理 1 行'), findsOneWidget);

      await tester.tap(find.byTooltip('试听第 2 行'));
      expect(previewed, [1]);

      await tester.tap(find.byKey(const ValueKey('word_check_confirm')));
      await tester.pumpAndSettle();
      final edit = result()!;
      expect(edit.document.lines.first.words, isEmpty);
      expect(edit.document.lines[1].words, hasLength(2));
      expect(edit.selectedLineIndex, 0);
      expect(edit.message, LyricWordTimingCheckStrings.applied(1));
    });

    testWidgets('a project without word timing points to the tools', (
      tester,
    ) async {
      await _open(
        tester,
        () => LyricWordTimingCheckDialog(
          document: LyricDocument(
            language: 'zh',
            lines: [
              LyricLine(text: '一行', startTime: _ms(0), endTime: _ms(1000)),
            ],
          ),
        ),
      );
      expect(find.text('没有发现问题。'), findsOneWidget);
      expect(find.textContaining('「逐字打轴」'), findsOneWidget);
      expect(find.text('没有需要整理的行'), findsOneWidget);
    });
  });

  group('LyricWordTimingEditDialog', () {
    final document = LyricDocument(
      language: 'zh',
      lines: [
        LyricLine(
          id: 'a',
          text: '我爱你',
          startTime: _ms(1000),
          endTime: _ms(2000),
          words: [
            _w('我', 1000, 1300),
            _w('爱', 1300, 1600),
            _w('你', 1600, 2000),
          ],
        ),
        LyricLine(text: '你好', startTime: _ms(3000), endTime: _ms(4000)),
      ],
    );

    testWidgets('nudges a boundary with buttons and keys, then applies', (
      tester,
    ) async {
      final result = await _open(
        tester,
        () => LyricWordTimingEditDialog(document: document, index: 0),
      );
      expect(find.text('还没有改动'), findsOneWidget);
      expect(find.byKey(const ValueKey('word_edit_play')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('word_edit_chip_1')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('word_edit_start_50')));
      await tester.pump();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('word_edit_selected')))
            .data,
        contains('0.25 秒'),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await tester.pump();
      // Undo the last key, then apply.
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('word_edit_confirm')));
      await tester.pumpAndSettle();
      final edit = result()!;
      expect(_times(edit.document.lines.first), [
        ('我', 1000, 1350),
        ('爱', 1350, 1610),
        ('你', 1610, 2000),
      ]);
      expect(edit.selectedLineIndex, 0);
      expect(edit.message, LyricWordTimingEditStrings.applied(1));
    });

    testWidgets('a row without word timing starts from the estimate', (
      tester,
    ) async {
      final result = await _open(
        tester,
        () => LyricWordTimingEditDialog(document: document, index: 1),
      );
      expect(find.byKey(const ValueKey('word_edit_estimated')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('word_edit_merge')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('word_edit_confirm')));
      await tester.pumpAndSettle();
      expect(_times(result()!.document.lines[1]), [('你好', 3000, 4000)]);
    });

    testWidgets('auditions the word and sets its start at the playhead', (
      tester,
    ) async {
      final player = _FakePlayer();
      final result = await _open(
        tester,
        () => LyricWordTimingEditDialog(
          document: document,
          index: 0,
          transport: player.transport,
          now: () => Duration.zero,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('word_edit_chip_2')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('word_edit_play')));
      await tester.pump();
      expect(player.seeks, [_ms(1300)]);
      expect(player.state.isPlaying, isTrue);
      player.report(player.state.copyWith(position: _ms(2250)));
      await tester.pump();
      expect(player.pauses, 1);

      await tester.tap(find.byKey(const ValueKey('word_edit_start_playhead')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('word_edit_fit')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('word_edit_confirm')));
      await tester.pumpAndSettle();
      final line = result()!.document.lines.first;
      expect(_times(line).last, ('你', 1960, 2000));
      expect(_times(line)[1], ('爱', 1300, 1960));
    });
  });

  testWidgets('the strip opens fine-tuning', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LyricWordTimingStrip(
            line: LyricLine(
              text: '我爱',
              startTime: _ms(0),
              endTime: _ms(1000),
              words: [_w('我', 0, 500), _w('爱', 500, 1000)],
            ),
            onEdit: () => opened++,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('word_timing_edit')));
    expect(opened, 1);
  });

  testWidgets('the proofread menu offers the word timing check', (
    tester,
  ) async {
    var fired = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: LyricProofreadMenuButton(onWordTimingCheck: () => fired++),
          ),
        ),
      ),
    );
    await tester.tap(find.text(LyricProofreadMenuButton.label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(LyricWordTimingCheckStrings.actionTitle));
    await tester.pumpAndSettle();
    expect(fired, 1);
  });

  test('the summary card hints at stale word timing', () {
    final hints = LyricRecognitionSummaryCard.healthHints(
      const LyricDraftHealth(
        captionRows: 0,
        repetitionGroups: 0,
        longLines: 0,
        fragments: 0,
        paceRows: 1,
        staleWordRows: 2,
      ),
    );
    expect(hints.map((h) => h.tool), [
      LyricBatchTextTool.paceCheck,
      LyricBatchTextTool.wordTimingCheck,
    ]);
    expect(hints.last.label, '逐字时间失效 2 行');
  });
}

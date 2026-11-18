import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_draft_health_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_batch_text_edit.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_export_dialog.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_pace_check_dialog.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_proofread_menu_button.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_recognition_summary_card.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_tap_sync_dialog.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_state.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

// Every lyric below is synthetic text written for these tests.
LyricLine _line(String text, int startMs, int endMs, {String? id}) => LyricLine(
  text: text,
  startTime: Duration(milliseconds: startMs),
  endTime: Duration(milliseconds: endMs),
  id: id,
);

LyricDocument _doc(List<LyricLine> lines) =>
    LyricDocument(language: 'zh', lines: lines);

List<(int, int)> _spans(LyricDocument document) => [
  for (final l in document.lines)
    (l.startTime.inMilliseconds, l.endTime.inMilliseconds),
];

Duration _ms(int value) => Duration(milliseconds: value);

Future<T? Function()> _openDialog<T>(
  WidgetTester tester,
  Future<T?> Function(BuildContext context) open,
) async {
  T? result;
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async => result = await open(context),
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

/// A player double: play/pause/seek update its state and report it.
class _FakePlayer {
  final StreamController<PlaybackState> _states =
      StreamController<PlaybackState>.broadcast();
  PlaybackState state = const PlaybackState.idle();
  final List<Duration> seeks = [];
  final List<double> speeds = [];
  int pauses = 0;
  Duration now = Duration.zero;

  /// While set, play fails the way a player without a source does.
  Object? playFailure;

  void report(PlaybackState next) {
    state = next;
    _states.add(next);
  }

  /// The player reports [ms] while playing.
  void at(int ms) => report(state.copyWith(isPlaying: true, position: _ms(ms)));

  LyricTapSyncTransport get transport => LyricTapSyncTransport(
    currentState: () => state,
    states: _states.stream,
    play: () async {
      final failure = playFailure;
      if (failure != null) throw failure;
      report(state.copyWith(isPlaying: true));
    },
    pause: () async {
      pauses++;
      report(state.copyWith(isPlaying: false));
    },
    seek: (position) async {
      seeks.add(position);
      report(state.copyWith(position: position));
    },
    setSpeed: (speed) async {
      speeds.add(speed);
      report(state.copyWith(speed: speed));
    },
  );
}

void main() {
  group('LyricTapSyncDialog', () {
    final song = _doc([
      _line('第一句', 5000, 7000, id: 'a'),
      _line('第二句', 8000, 10000, id: 'b'),
      _line('第三句', 11000, 13000, id: 'c'),
    ]);

    Future<(LyricBatchTextEdit? Function(), _FakePlayer)> open(
      WidgetTester tester, {
      int startIndex = 0,
    }) async {
      final player = _FakePlayer();
      final result = await _openDialog<LyricBatchTextEdit>(
        tester,
        (context) => showDialog<LyricBatchTextEdit>(
          context: context,
          builder: (_) => LyricTapSyncDialog(
            document: song,
            startIndex: startIndex,
            transport: player.transport,
            now: () => player.now,
          ),
        ),
      );
      return (result, player);
    }

    Future<void> space(WidgetTester tester) async {
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
    }

    String progress(WidgetTester tester) => tester
        .widget<Text>(find.byKey(const ValueKey('tap_sync_progress')))
        .data!;

    testWidgets('opens before the first row, taps rows in order and applies', (
      tester,
    ) async {
      final (result, player) = await open(tester);
      // Paused on open: the player is moved three seconds before row 1.
      expect(player.seeks, [_ms(2000)]);
      expect(find.text('开始播放（空格）'), findsOneWidget);

      // The first press while paused starts playback instead of timing.
      await space(tester);
      expect(player.state.isPlaying, isTrue);
      expect(progress(tester), '已打 0 行 · 还剩 3 行');

      player.at(5200);
      await tester.pump();
      await space(tester);
      player.at(8100);
      await tester.pump();
      await space(tester);
      expect(progress(tester), '已打 2 行 · 还剩 1 行');

      // Undo takes back row 2 and resumes two seconds before it.
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(progress(tester), '已打 1 行 · 还剩 2 行');
      expect(player.seeks.last, _ms(6100));

      player.at(8300);
      await tester.pump();
      await space(tester);
      expect(find.text('应用 2 行'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('tap_sync_confirm')));
      await tester.pumpAndSettle();
      final edit = result()!;
      expect(_spans(edit.document), [
        (5200, 8300),
        (8300, 11000),
        (11000, 13000),
      ]);
      expect(edit.selectedLineIndex, 1);
      expect(edit.message, LyricTapSyncStrings.applied(2, 0));
      // Closing the dialog stops the song.
      expect(player.pauses, greaterThan(0));
    });

    testWidgets('a player that refuses to play says so until it recovers', (
      tester,
    ) async {
      final (_, player) = await open(tester);
      player.playFailure = StateError('no audio source');

      await space(tester);
      await tester.pump();
      expect(player.state.isPlaying, isFalse);
      expect(find.textContaining('播放失败'), findsOneWidget);
      expect(progress(tester), '已打 0 行 · 还剩 3 行');

      player.playFailure = null;
      await space(tester);
      await tester.pump();
      expect(player.state.isPlaying, isTrue);
      expect(find.textContaining('播放失败'), findsNothing);
    });

    testWidgets('extrapolates the position between player reports', (
      tester,
    ) async {
      final (result, player) = await open(tester);
      player.at(5000);
      await tester.pump();
      player.now = const Duration(milliseconds: 180);
      await space(tester);
      await tester.tap(find.byKey(const ValueKey('tap_sync_confirm')));
      await tester.pumpAndSettle();
      expect(_spans(result()!.document).first.$1, 5180);
    });

    testWidgets('hold mode records the release as the end', (tester) async {
      final (result, player) = await open(tester, startIndex: 1);
      await tester.ensureVisible(find.text('按住：按下开始、松开结束'));
      await tester.tap(find.text('按住：按下开始、松开结束'));
      await tester.pump();
      player.at(8000);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await tester.pump();
      player.at(9500);
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('tap_sync_confirm')));
      await tester.pumpAndSettle();
      expect(_spans(result()!.document), [
        (5000, 7000),
        (8000, 9500),
        (11000, 13000),
      ]);
    });

    testWidgets('reaction compensation and speed are applied', (tester) async {
      final (result, player) = await open(tester);
      await tester.ensureVisible(
        find.byKey(const ValueKey('tap_sync_speed_0.5')),
      );
      await tester.tap(find.byKey(const ValueKey('tap_sync_speed_0.5')));
      await tester.pump();
      expect(player.speeds, [0.5]);
      await tester.ensureVisible(
        find.byKey(const ValueKey('tap_sync_latency_150')),
      );
      await tester.tap(find.byKey(const ValueKey('tap_sync_latency_150')));
      await tester.pump();
      player.at(6000);
      await tester.pump();
      await space(tester);
      await tester.tap(find.byKey(const ValueKey('tap_sync_confirm')));
      await tester.pumpAndSettle();
      // 150 ms of reaction time is 75 ms of audio at half speed.
      expect(_spans(result()!.document).first.$1, 5925);
      // The original speed comes back when the dialog closes.
      expect(player.speeds.last, 1.0);
    });

    testWidgets('the pad times rows on pointer down', (tester) async {
      final (result, player) = await open(tester);
      player.at(5100);
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('tap_sync_pad')));
      await tester.tap(find.byKey(const ValueKey('tap_sync_pad')));
      await tester.pump();
      expect(progress(tester), '已打 1 行 · 还剩 2 行');
      await tester.tap(find.byKey(const ValueKey('tap_sync_confirm')));
      await tester.pumpAndSettle();
      expect(_spans(result()!.document).first, (5100, 8000));
    });
  });

  group('LyricPaceCheckDialog', () {
    final song = _doc([
      _line('春风吹过山岗', 0, 2000),
      _line('细雨落在窗前', 3000, 5000),
      _line('我们走过长街', 6000, 8000),
      _line('一二三四五六七八九十百千', 9000, 10000),
      _line('灯火照亮归途', 12000, 14000),
      _line('啊啊啊啊', 15000, 25000),
      _line('明天还会再见', 27000, 29000),
      _line('星光洒满天空', 30000, 32000),
      _line('故事还没说完', 33000, 35000),
    ]);

    testWidgets('lists both kinds, pre-selects proposals and applies them', (
      tester,
    ) async {
      final previewed = <int>[];
      final result = await _openDialog<LyricBatchTextEdit>(
        tester,
        (context) => showLyricPaceCheckDialog(
          context,
          document: song,
          protectedIndices: const {},
          onPreviewLine: previewed.add,
        ),
      );
      expect(find.text('过快 1 行，过慢 1 行；其中 2 行可按时间调整。'), findsOneWidget);
      expect(find.textContaining('全曲语速中位数：每秒 3.0 字'), findsOneWidget);
      expect(find.text('调整 2 行'), findsOneWidget);

      await tester.tap(find.byTooltip('试听第 6 行'));
      expect(previewed, [5]);

      await tester.tap(find.byKey(const ValueKey('pace_check_toggle_all')));
      await tester.pump();
      expect(find.text('请选择要调整的行'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pace_check_toggle_all')));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('pace_check_confirm')));
      await tester.pumpAndSettle();
      final edit = result()!;
      expect(_spans(edit.document)[3], (9000, 11900));
      expect(_spans(edit.document)[5], (15000, 16870));
      expect(edit.selectedLineIndex, 3);
    });

    testWidgets('a steady song has nothing to adjust', (tester) async {
      await _openDialog<LyricBatchTextEdit>(
        tester,
        (context) => showLyricPaceCheckDialog(
          context,
          document: _doc([
            for (var i = 0; i < 6; i++)
              _line('春风吹过山岗', i * 3000, i * 3000 + 2000),
          ]),
          protectedIndices: const {},
        ),
      );
      expect(find.text('没有发现语速异常的行。'), findsOneWidget);
      expect(find.text('没有可自动调整的行'), findsOneWidget);
    });
  });

  testWidgets('the proofread menu offers the pace check and tap-to-sync', (
    tester,
  ) async {
    final fired = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: LyricProofreadMenuButton(
              onPaceCheck: () => fired.add('pace'),
              onTapSync: () => fired.add('tap'),
            ),
          ),
        ),
      ),
    );
    for (final entry in {
      LyricPaceCheckStrings.actionTitle: 'pace',
      LyricTapSyncStrings.actionTitle: 'tap',
    }.entries) {
      await tester.tap(find.text(LyricProofreadMenuButton.label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(entry.key));
      await tester.pumpAndSettle();
      expect(fired.last, entry.value);
    }
  });

  test('the summary card hints at pace issues last', () {
    final hints = LyricRecognitionSummaryCard.healthHints(
      const LyricDraftHealth(
        captionRows: 0,
        repetitionGroups: 0,
        longLines: 0,
        fragments: 0,
        timelineRows: 1,
        paceRows: 2,
      ),
    );
    expect(hints.map((h) => h.tool), [
      LyricBatchTextTool.timelineRepair,
      LyricBatchTextTool.paceCheck,
    ]);
    expect(hints.last.label, '语速异常 2 行');
  });

  testWidgets('the export dialog previews ASS karaoke with a lead-in switch', (
    tester,
  ) async {
    final result = await _openDialog<LyricExportRequest>(
      tester,
      (context) => showLyricExportDialog(
        context,
        document: _doc([_line('我爱你', 2000, 3500)]),
      ),
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('lyric_export_format_ass')),
    );
    await tester.tap(find.byKey(const ValueKey('lyric_export_format_ass')));
    await tester.pumpAndSettle();
    String preview() => tester
        .widget<SelectableText>(
          find.descendant(
            of: find.byKey(const ValueKey('lyric_export_preview')),
            matching: find.byType(SelectableText),
          ),
        )
        .data!;
    // The fixed script and style header is skipped in the preview.
    expect(preview(), startsWith('…（已省略脚本信息和样式）\n[Events]'));
    expect(preview(), isNot(contains('[Script Info]')));
    expect(preview(), contains('{\\k100}{\\kf50}我'));
    expect(find.textContaining('逐字时间按每行'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('lyric_export_ass_lead_in')),
    );
    await tester.tap(find.byKey(const ValueKey('lyric_export_ass_lead_in')));
    await tester.pumpAndSettle();
    expect(preview(), isNot(contains('{\\k100}')));

    await tester.tap(find.byKey(const ValueKey('lyric_export_confirm')));
    await tester.pumpAndSettle();
    expect(result()!.format.name, 'ass');
    expect(result()!.options.assLeadIn, Duration.zero);
  });
}

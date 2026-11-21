import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/project/presentation/widgets/recognition_progress_card.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_run_progress.dart';

// D-049: while lyrics are recognised the project page names the step, keeps
// a stopwatch running and says so when the program has been quiet.

final _t0 = DateTime(2026, 11, 18, 9);

class _Clock {
  DateTime now = _t0;

  void advance(Duration by) => now = now.add(by);
}

Future<void> _pump(
  WidgetTester tester,
  TranscriptionRunTracker tracker,
  _Clock clock, {
  VoidCallback? onCancel,
  bool disableAnimations = false,
}) async {
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(1200, 1000),
          disableAnimations: disableAnimations,
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            child: RecognitionProgressCard(
              tracker: tracker,
              onCancel: onCancel,
              clock: () => clock.now,
            ),
          ),
        ),
      ),
    ),
  );
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

TranscriptionProgress _event(
  TranscriptionRunStep step,
  double overall, {
  String message = '',
}) => TranscriptionProgress(
  stage: TranscriptionStage.transcribing,
  progress: 0,
  message: message,
  step: step,
  overall: overall,
);

void main() {
  testWidgets('starts with the first step, 0% and the stopwatch at 0:00', (
    tester,
  ) async {
    final clock = _Clock();
    await _pump(tester, TranscriptionRunTracker(startedAt: _t0), clock);

    expect(_text(tester, 'recognition_progress_title'), '正在准备识别');
    expect(_text(tester, 'recognition_progress_percent'), '0%');
    expect(
      _text(tester, 'recognition_progress_elapsed'),
      '第 1/6 步 · 已用时 0:00',
    );
    expect(
      _text(tester, 'recognition_progress_message'),
      TranscriptionRunText.preparingMessage,
    );
    expect(_text(tester, 'recognition_progress_remaining'), '正在估算剩余时间');
    expect(find.byKey(const ValueKey('recognition_progress_quiet')), findsNothing);
    for (final step in TranscriptionRunStep.values) {
      expect(find.byKey(ValueKey('recognition_step_${step.name}')), findsOneWidget);
    }
  });

  testWidgets('the stopwatch moves every second without any event', (
    tester,
  ) async {
    final clock = _Clock();
    await _pump(tester, TranscriptionRunTracker(startedAt: _t0), clock);

    clock.advance(const Duration(seconds: 7));
    await tester.pump(const Duration(seconds: 1));
    expect(
      _text(tester, 'recognition_progress_elapsed'),
      '第 1/6 步 · 已用时 0:07',
    );
  });

  testWidgets('shows the step, the message and the overall of the run', (
    tester,
  ) async {
    final clock = _Clock();
    final tracker = TranscriptionRunTracker(startedAt: _t0)
      ..record(
        _event(
          TranscriptionRunStep.recognizing,
          0.55,
          message: 'Qwen3-ASR 识别中',
        ),
        _t0.add(const Duration(seconds: 60)),
      );
    clock.advance(const Duration(seconds: 61));
    await _pump(tester, tracker, clock);

    expect(_text(tester, 'recognition_progress_title'), '正在识别歌词');
    expect(_text(tester, 'recognition_progress_percent'), '55%');
    expect(
      _text(tester, 'recognition_progress_elapsed'),
      '第 3/6 步 · 已用时 1:01',
    );
    expect(_text(tester, 'recognition_progress_message'), 'Qwen3-ASR 识别中');
    expect(_text(tester, 'recognition_progress_remaining'), '预计不到 1 分钟');
    final bars = tester.widgetList<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bars.map((bar) => bar.value), contains(closeTo(0.55, 1e-9)));
    // The sweep behind the bar shows activity while the number stands still.
    expect(
      find.byKey(const ValueKey('recognition_progress_activity')),
      findsOneWidget,
    );
  });

  testWidgets('after twenty quiet seconds it says the program still runs', (
    tester,
  ) async {
    final clock = _Clock();
    final tracker = TranscriptionRunTracker(startedAt: _t0)
      ..record(_event(TranscriptionRunStep.recognizing, 0.3), _t0);
    await _pump(tester, tracker, clock);
    expect(find.byKey(const ValueKey('recognition_progress_quiet')), findsNothing);

    clock.advance(const Duration(seconds: 25));
    await tester.pump(const Duration(seconds: 1));
    final quiet = find.byKey(const ValueKey('recognition_progress_quiet'));
    expect(quiet, findsOneWidget);
    expect(
      find.descendant(
        of: quiet,
        matching: find.textContaining('已 25 秒没有新的进度消息'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: quiet, matching: find.textContaining('1 到 5 分钟')),
      findsOneWidget,
    );
  });

  testWidgets('the step row marks skipped steps', (tester) async {
    final semantics = tester.ensureSemantics();
    final clock = _Clock();
    final tracker = TranscriptionRunTracker(startedAt: _t0)
      ..record(_event(TranscriptionRunStep.recognizing, 0.3), _t0);
    await _pump(tester, tracker, clock);

    expect(find.text('分离人声（跳过）'), findsOneWidget);
    expect(find.text('识别歌词'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
    expect(find.bySemanticsLabel('准备，已完成'), findsOneWidget);
    expect(find.bySemanticsLabel('分离人声，已跳过'), findsOneWidget);
    expect(find.bySemanticsLabel('识别歌词，进行中'), findsOneWidget);
    expect(find.bySemanticsLabel('保存，等待中'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('the stop button calls back; without one there is none', (
    tester,
  ) async {
    final clock = _Clock();
    var stops = 0;
    await _pump(
      tester,
      TranscriptionRunTracker(startedAt: _t0),
      clock,
      onCancel: () => stops++,
    );
    await tester.tap(find.byKey(const ValueKey('recognition_progress_cancel')));
    expect(stops, 1);

    await _pump(tester, TranscriptionRunTracker(startedAt: _t0), clock);
    expect(
      find.byKey(const ValueKey('recognition_progress_cancel')),
      findsNothing,
    );
  });

  testWidgets('with reduced motion nothing spins or sweeps', (tester) async {
    final clock = _Clock();
    await _pump(
      tester,
      TranscriptionRunTracker(startedAt: _t0),
      clock,
      disableAnimations: true,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.byKey(const ValueKey('recognition_progress_activity')),
      findsNothing,
    );
    expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);
  });

  testWidgets('the stopwatch stops when the card goes away', (tester) async {
    final clock = _Clock();
    await _pump(tester, TranscriptionRunTracker(startedAt: _t0), clock);
    await tester.pumpWidget(const SizedBox());
    // A periodic timer left running would fail the test here.
    await tester.pump(const Duration(seconds: 3));
  });
}

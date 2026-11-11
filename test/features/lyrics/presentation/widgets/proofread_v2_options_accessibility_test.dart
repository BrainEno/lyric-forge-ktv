import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/proofread_strategy_selector.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_proofread_v2_dialog.dart';

void main() {
  final scenarios = <({Size size, double scale})>[
    (size: const Size(320, 568), scale: 1),
    (size: const Size(320, 568), scale: 2),
    (size: const Size(800, 480), scale: 1),
    (size: const Size(800, 480), scale: 2),
  ];

  for (final scenario in scenarios) {
    testWidgets('options are scrollable and actions reachable: $scenario', (
      tester,
    ) async {
      ProofreadV2RunOptions? result;
      await _configureView(tester, scenario.size);
      await tester.pumpWidget(
        _host(scale: scenario.scale, onResult: (value) => result = value),
      );
      await _open(tester);
      _expectNoException(tester, 'opening');

      await tester.ensureVisible(find.text('ASR 优先'));
      await tester.tap(find.text('ASR 优先'));
      await tester.pumpAndSettle();
      _expectNoException(tester, 'switching strategy');

      final toggle = find.byKey(
        const ValueKey('forced_alignment_review_toggle'),
      );
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      _expectNoException(tester, 'toggling alignment');

      final field = find.byKey(
        const ValueKey('secondary_asr_transcript_input'),
      );
      await tester.ensureVisible(field);
      await tester.enterText(field, '[00:01.00] 第一行\n[00:02.00] second line');
      await tester.pumpAndSettle();
      _expectNoException(tester, 'entering text');

      expect(find.text('取消').hitTestable(), findsOneWidget);
      expect(find.text('继续').hitTestable(), findsOneWidget);
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();
      _expectNoException(tester, 'continuing');
      expect(result?.strategy, LyricSourceStrategy.asrFirst);
      expect(result?.useForcedAlignment, isTrue);
      expect(
        result?.secondaryTranscriptText,
        '[00:01.00] 第一行\n[00:02.00] second line',
      );
    });

    testWidgets('cancel stays reachable after scrolling: $scenario', (
      tester,
    ) async {
      var completed = false;
      ProofreadV2RunOptions? result;
      await _configureView(tester, scenario.size);
      await tester.pumpWidget(
        _host(
          scale: scenario.scale,
          onResult: (value) {
            completed = true;
            result = value;
          },
        ),
      );
      await _open(tester);
      await tester.ensureVisible(find.text('ASR 优先'));
      await tester.tap(find.text('ASR 优先'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('secondary_asr_transcript_input')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('secondary_asr_transcript_input')),
        'long draft',
      );
      await tester.pumpAndSettle();
      expect(find.text('取消').hitTestable(), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(completed, isTrue);
      expect(result, isNull);
      _expectNoException(tester, 'cancelling');
    });
  }

  testWidgets('long pasted input survives scrolling and strategy changes', (
    tester,
  ) async {
    ProofreadV2RunOptions? result;
    await _configureView(tester, const Size(320, 568));
    await tester.pumpWidget(
      _host(scale: 2, onResult: (value) => result = value),
    );
    await _open(tester);
    await tester.ensureVisible(find.text('ASR 优先'));
    await tester.tap(find.text('ASR 优先'));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('secondary_asr_transcript_input'));
    await tester.ensureVisible(field);
    final text = List.generate(60, (i) => '[00:01.00] 第$i行 🙂').join('\n');
    await tester.enterText(field, text);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('参考歌词优先'));
    await tester.tap(find.text('参考歌词优先'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('ASR 优先'));
    await tester.tap(find.text('ASR 优先'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(field);
    expect(tester.widget<TextField>(field).controller!.text, text);
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    expect(result?.secondaryTranscriptText, text);
    _expectNoException(tester, 'long input');
  });

  testWidgets('empty secondary input stays optional', (tester) async {
    ProofreadV2RunOptions? result;
    await _configureView(tester, const Size(320, 568));
    await tester.pumpWidget(
      _host(scale: 2, onResult: (value) => result = value),
    );
    await _open(tester);
    await tester.ensureVisible(find.text('ASR 优先'));
    await tester.tap(find.text('ASR 优先'));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('secondary_asr_transcript_input'));
    await tester.ensureVisible(field);
    await tester.enterText(field, '  \n  ');
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    expect(result?.secondaryTranscriptText, isNull);
    _expectNoException(tester, 'empty input');
  });

  testWidgets('strategy, alignment and actions have accessible semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _configureView(tester, const Size(320, 568));
    await tester.pumpWidget(_host(scale: 2, onResult: (_) {}));
    await _open(tester);
    await tester.ensureVisible(find.text('ASR 优先'));
    await tester.tap(find.text('ASR 优先'));
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('forced_alignment_review_toggle'));
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(RegExp('使用 ForcedAligner 词级时间证据')),
      findsWidgets,
    );
    expect(find.bySemanticsLabel(RegExp('继续')), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('取消')), findsWidgets);
    _expectNoException(tester, 'semantics');
    semantics.dispose();
  });

  testWidgets('keyboard traverses strategy, toggle, text and continue', (
    tester,
  ) async {
    ProofreadV2RunOptions? result;
    await _configureView(tester, const Size(320, 568));
    await tester.pumpWidget(
      _host(scale: 2, onResult: (value) => result = value),
    );
    await _open(tester);
    await _tabUntil(tester, find.text('ASR 优先'));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('forced_alignment_review_toggle'));
    await _tabUntil(tester, toggle);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('secondary_asr_transcript_input'));
    await _tabUntil(tester, field);
    await tester.enterText(field, '[00:01.00] keyboard');
    await tester.pumpAndSettle();
    await _tabUntil(tester, find.text('继续'));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(result?.strategy, LyricSourceStrategy.asrFirst);
    expect(result?.useForcedAlignment, isTrue);
    expect(result?.secondaryTranscriptText, '[00:01.00] keyboard');
    _expectNoException(tester, 'keyboard traversal');
  });
}

Future<void> _configureView(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _host({
  required double scale,
  required void Function(ProofreadV2RunOptions?) onResult,
}) {
  return MaterialApp(
    theme: ThemeData.dark(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Scaffold(
      body: Center(
        child: Builder(
          builder: (context) => FilledButton(
            onPressed: () async =>
                onResult(await showProofreadV2RunOptionsDialog(context)),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void _expectNoException(WidgetTester tester, String step) {
  final error = tester.takeException();
  expect(error, isNull, reason: 'Flutter error after $step: $error');
}

Future<void> _tabUntil(WidgetTester tester, Finder target) async {
  for (var i = 0; i < 20; i++) {
    final context = tester.element(target);
    if (Focus.of(context).hasFocus) {
      expect(
        target.hitTestable(),
        findsOneWidget,
        reason: 'focused control should be visible',
      );
      return;
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    _expectNoException(tester, 'tab');
  }
  fail('Could not focus $target with Tab');
}

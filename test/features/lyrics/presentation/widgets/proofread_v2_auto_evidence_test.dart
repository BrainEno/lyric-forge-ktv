import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/proofread_strategy_selector.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_proofread_v2_dialog.dart';

void main() {
  for (final size in [const Size(320, 568), const Size(800, 480)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('auto evidence remains reachable at $size scale $scale', (
        tester,
      ) async {
        ProofreadV2RunOptions? result;
        await configure(tester, size, scale, (value) => result = value);
        expect(find.text('自动选择'), findsOneWidget);
        expect(find.textContaining('第二份 ASR 仅在最终选择 ASR 优先时使用'), findsOneWidget);
        await tester.ensureVisible(find.text('本次提供参考歌词'));
        await tester.tap(find.text('本次提供参考歌词'));
        await tester.pumpAndSettle();
        final toggle = find.byKey(
          const ValueKey('forced_alignment_review_toggle'),
        );
        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        final field = find.byKey(
          const ValueKey('secondary_asr_transcript_input'),
        );
        await tester.ensureVisible(field);
        await tester.enterText(field, '  [00:01.00] 第一行 🙂  ');
        await tester.pumpAndSettle();
        expect(find.text('继续').hitTestable(), findsOneWidget);
        expect(find.text('取消').hitTestable(), findsOneWidget);
        await tester.tap(find.text('继续'));
        await tester.pumpAndSettle();
        expect(result?.strategy, LyricSourceStrategy.auto);
        expect(result?.useReference, isTrue);
        expect(result?.useForcedAlignment, isTrue);
        expect(result?.secondaryTranscriptText, '[00:01.00] 第一行 🙂');
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets('reference mode exposes alignment option at scale $scale', (
      tester,
    ) async {
      ProofreadV2RunOptions? result;
      await configure(
        tester,
        const Size(320, 568),
        scale,
        (value) => result = value,
      );
      await tester.ensureVisible(find.text('参考歌词优先'));
      await tester.tap(find.text('参考歌词优先'));
      await tester.pumpAndSettle();
      final toggle = find.byKey(
        const ValueKey('forced_alignment_review_toggle'),
      );
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.textContaining('参考优先对齐参考文本'), findsOneWidget);
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();
      expect(result!.strategy, LyricSourceStrategy.referenceFirst);
      expect(result!.useReference, isTrue);
      expect(result!.useForcedAlignment, isTrue);
      expect(result!.secondaryTranscriptText, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('automatic defaults do not request evidence or reference', (
    tester,
  ) async {
    ProofreadV2RunOptions? result;
    await configure(tester, const Size(800, 600), 1, (value) => result = value);
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    expect(result?.strategy, LyricSourceStrategy.auto);
    expect(result?.useReference, isFalse);
    expect(result?.useForcedAlignment, isFalse);
    expect(result?.secondaryTranscriptText, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reference-first keeps alignment but suppresses previously entered second ASR',
    (tester) async {
      ProofreadV2RunOptions? result;
      await configure(
        tester,
        const Size(800, 600),
        1,
        (value) => result = value,
      );
      final toggle = find.byKey(
        const ValueKey('forced_alignment_review_toggle'),
      );
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      final field = find.byKey(
        const ValueKey('secondary_asr_transcript_input'),
      );
      await tester.ensureVisible(field);
      await tester.enterText(field, '[00:01.00] evidence');
      await tester.ensureVisible(find.text('参考歌词优先'));
      await tester.tap(find.text('参考歌词优先'));
      await tester.pumpAndSettle();
      expect(find.textContaining('之前配置的 ASR 第二意见'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('secondary_asr_transcript_input')),
        findsNothing,
      );
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();
      expect(result?.strategy, LyricSourceStrategy.referenceFirst);
      expect(result?.useReference, isTrue);
      expect(result?.useForcedAlignment, isTrue);
      expect(result?.secondaryTranscriptText, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('switching back to auto restores both options', (tester) async {
    ProofreadV2RunOptions? result;
    await configure(tester, const Size(800, 600), 1, (value) => result = value);
    final toggle = find.byKey(const ValueKey('forced_alignment_review_toggle'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    final field = find.byKey(const ValueKey('secondary_asr_transcript_input'));
    await tester.ensureVisible(field);
    await tester.enterText(field, '[00:01.00] preserved');
    await tester.ensureVisible(find.text('参考歌词优先'));
    await tester.tap(find.text('参考歌词优先'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自动选择'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(field);
    expect(
      tester.widget<TextField>(field).controller!.text,
      '[00:01.00] preserved',
    );
    expect(tester.widget<CheckboxListTile>(toggle).value, isTrue);
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    expect(result?.strategy, LyricSourceStrategy.auto);
    expect(result?.useForcedAlignment, isTrue);
    expect(result?.secondaryTranscriptText, '[00:01.00] preserved');
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard can configure auto evidence at large text size', (
    tester,
  ) async {
    ProofreadV2RunOptions? result;
    await configure(tester, const Size(320, 568), 2, (value) => result = value);
    final toggle = find.byKey(const ValueKey('forced_alignment_review_toggle'));
    await tabUntil(tester, toggle);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('secondary_asr_transcript_input'));
    await tabUntil(tester, field);
    await tester.enterText(field, '[00:01.00] keyboard');
    await tabUntil(tester, find.text('继续'));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(result?.strategy, LyricSourceStrategy.auto);
    expect(result?.useForcedAlignment, isTrue);
    expect(result?.secondaryTranscriptText, '[00:01.00] keyboard');
    expect(tester.takeException(), isNull);
  });
}

Future<void> configure(
  WidgetTester tester,
  Size size,
  double scale,
  void Function(ProofreadV2RunOptions?) onResult,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () async =>
                onResult(await showProofreadV2RunOptionsDialog(context)),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> tabUntil(WidgetTester tester, Finder target) async {
  for (var i = 0; i < 30; i++) {
    final element = target.evaluate().single;
    final focus = Focus.maybeOf(element);
    if (focus?.hasFocus ?? false) return;
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
  }
  fail('Could not focus $target');
}

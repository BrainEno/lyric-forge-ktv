import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';
import 'package:lyric_forge_ktv/features/project/presentation/widgets/production_steps.dart';

List<ProductionStepState> _states(
  ProcessingStage stage, {
  bool transcribing = false,
}) => [
  for (final step in productionStepsFor(stage, transcribing: transcribing))
    step.state,
];

const _done = ProductionStepState.done;
const _running = ProductionStepState.inProgress;
const _next = ProductionStepState.next;
const _later = ProductionStepState.upcoming;

Future<void> _pump(WidgetTester tester, List<ProductionStep> steps) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 296, child: ProductionSteps(steps: steps)),
        ),
      ),
    ),
  );
}

void main() {
  group('productionStepsFor', () {
    test('lists the five steps in order', () {
      final steps = productionStepsFor(ProcessingStage.none);
      final labels = [for (final step in steps) step.label];
      expect(labels, ['导入', '音频处理', '歌词识别', '歌词校对', '导出']);
    });

    test('a new project has the import as its next step', () {
      expect(_states(ProcessingStage.none), [
        _next,
        _later,
        _later,
        _later,
        _later,
      ]);
    });

    test('marks every passed step done and the first open one next', () {
      expect(_states(ProcessingStage.audioImported), [
        _done,
        _next,
        _later,
        _later,
        _later,
      ]);
      expect(_states(ProcessingStage.transcriptionComplete), [
        _done,
        _done,
        _done,
        _next,
        _later,
      ]);
      expect(_states(ProcessingStage.lyricsEdited), [
        _done,
        _done,
        _done,
        _done,
        _next,
      ]);
    });

    test('vocal separation counts as past audio processing', () {
      expect(_states(ProcessingStage.vocalsSeparated), [
        _done,
        _done,
        _next,
        _later,
        _later,
      ]);
    });

    test('an exported project has nothing left', () {
      final steps = productionStepsFor(ProcessingStage.exported);
      expect(steps.every((step) => step.isDone), isTrue);
      expect(steps.any((step) => step.isCurrent), isFalse);
    });

    test('a running recognition is the only current step', () {
      expect(_states(ProcessingStage.audioImported, transcribing: true), [
        _done,
        _later,
        _running,
        _later,
        _later,
      ]);
    });

    test('a finished recognition stays done while a rerun starts', () {
      expect(_states(ProcessingStage.lyricsEdited, transcribing: true), [
        _done,
        _done,
        _done,
        _done,
        _later,
      ]);
    });

    test('state words', () {
      String word(ProductionStepState state) =>
          ProductionStep(label: '导入', icon: Icons.abc, state: state).stateLabel;
      expect(word(_done), '已完成');
      expect(word(_running), '进行中');
      expect(word(_next), '下一步');
      expect(word(_later), '未开始');
    });
  });

  group('ProductionSteps', () {
    testWidgets('fits all five steps in a phone-width card', (tester) async {
      await _pump(tester, productionStepsFor(ProcessingStage.audioImported));

      expect(tester.takeException(), isNull);
      for (final label in ['导入', '音频处理', '歌词识别', '歌词校对', '导出']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.byType(Scrollable), findsNothing);
      final first = tester.getRect(find.byKey(ProductionSteps.stepKey(0)));
      final last = tester.getRect(find.byKey(ProductionSteps.stepKey(4)));
      expect(first.top, last.top);
      expect(last.right - first.left, closeTo(296, 1));
    });

    testWidgets('done steps show a check instead of their icon', (
      tester,
    ) async {
      await _pump(
        tester,
        productionStepsFor(ProcessingStage.transcriptionComplete),
      );

      expect(find.byIcon(Icons.check_rounded), findsNWidgets(3));
      expect(find.byIcon(Icons.audio_file_outlined), findsNothing);
      expect(find.byIcon(Icons.edit_note_rounded), findsOneWidget);
      expect(find.byIcon(Icons.ios_share_rounded), findsOneWidget);
    });

    testWidgets('each step reads its position, label and state', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final steps = productionStepsFor(
        ProcessingStage.audioImported,
        transcribing: true,
      );
      await _pump(tester, steps);

      expect(ProductionSteps.semanticsLabelFor(steps, 0), '第 1 步，共 5 步：导入，已完成');
      expect(find.bySemanticsLabel('第 3 步，共 5 步：歌词识别，进行中'), findsOneWidget);
      expect(find.bySemanticsLabel('第 5 步，共 5 步：导出，未开始'), findsOneWidget);
      // The visible label is not read a second time.
      expect(find.bySemanticsLabel('歌词识别'), findsNothing);
      handle.dispose();
    });
  });
}

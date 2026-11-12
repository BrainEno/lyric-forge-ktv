import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/reference_lyric_input.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/reference_lyric_line.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/forced_alignment_proofread_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/proofread_review_proposal.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/reference_forced_alignment_planner.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_proofread_v2_dialog.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

void main() {
  final planner = const ReferenceForcedAlignmentPlanner();
  final input = planner.prepare(const ReferenceLyricInput(lines: [ReferenceLyricLine(text: 'reference')], timed: false, format: 'txt')).prepared!;
  final evidence = planner.plan(reference: input, spans: const [ForcedAlignedSpan(text: 'reference', start: Duration(seconds: 1), end: Duration(seconds: 2))], audioDuration: const Duration(seconds: 5)).proposals.single;
  const original = LyricLine(id: 'a', text: 'original', startTime: Duration.zero, endTime: Duration(milliseconds: 500));
  const proposed = LyricLine(id: 'a', text: 'reference', startTime: Duration.zero, endTime: Duration(milliseconds: 500));
  LyricProofreadV2Selection? selected;

  Future<void> open(WidgetTester tester, {bool allow = true, LyricProofreadReviewVerdict verdict = LyricProofreadReviewVerdict.amber, LyricLine? source = original, Duration offset = Duration.zero, Size size = const Size(800, 600), double scale = 1}) async {
    selected = null;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
      home: Scaffold(body: Builder(builder: (context) => TextButton(onPressed: () async {
        selected = await showLyricProofreadV2ReviewDialog(context, summary: 'summary', explanation: 'explanation', allowReferenceTimingSelection: allow, originalGlobalOffset: offset, items: [LyricProofreadV2ReviewItem(proposalIndex: 0, sourceIndex: source == null ? null : 0, originalLine: source, proposedLine: proposed, verdict: verdict, referenceTimingEvidence: evidence)], droppedItems: const [], onPreviewDraftLine: null);
      }, child: const Text('open')))),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder timing() => find.byKey(const ValueKey('accept_reference_timing_0'));
  Future<void> showTiming(WidgetTester tester) async {
    await tester.scrollUntilVisible(timing(), 100, scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)));
    await tester.pumpAndSettle();
  }
  Future<void> acceptText(WidgetTester tester) async {
    final textChoice = find.widgetWithText(CheckboxListTile, '采纳这条琥珀色建议');
    await Scrollable.ensureVisible(tester.element(textChoice), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(textChoice);
    await tester.pumpAndSettle();
  }

  testWidgets('text and timing are separate explicit choices', (tester) async {
    await open(tester);
    await showTiming(tester);
    expect(tester.widget<CheckboxListTile>(timing()).value, isFalse);
    expect(tester.widget<CheckboxListTile>(timing()).onChanged, isNull);
    await acceptText(tester);
    await showTiming(tester);
    expect(tester.widget<CheckboxListTile>(timing()).onChanged, isNotNull);
    await tester.tap(timing());
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('应用所选（琥珀色'));
    await tester.pumpAndSettle();
    expect(selected!.acceptedProposalIndices, {0});
    expect(selected!.acceptedReferenceTimingIndices, {0});
  });

  testWidgets('deselecting text clears now-incompatible timing choice', (tester) async {
    await open(tester);
    await acceptText(tester);
    await showTiming(tester);
    await tester.tap(timing());
    await tester.pumpAndSettle();
    await acceptText(tester);
    await showTiming(tester);
    expect(tester.widget<CheckboxListTile>(timing()).value, isFalse);
    expect(tester.widget<CheckboxListTile>(timing()).onChanged, isNull);
  });

  testWidgets('new row requires accepting the insertion first', (tester) async {
    await open(tester, source: null);
    await showTiming(tester);
    expect(tester.widget<CheckboxListTile>(timing()).onChanged, isNull);
    await acceptText(tester);
    await showTiming(tester);
    expect(tester.widget<CheckboxListTile>(timing()).onChanged, isNotNull);
  });

  testWidgets('protected rows and unverified audio are never selectable', (tester) async {
    await open(tester, verdict: LyricProofreadReviewVerdict.locked, source: proposed);
    await showTiming(tester);
    expect(tester.widget<CheckboxListTile>(timing()).onChanged, isNull);
    expect(find.textContaining('受保护行不可更改时间'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await open(tester, allow: false, source: proposed);
    await showTiming(tester);
    expect(tester.widget<CheckboxListTile>(timing()).onChanged, isNull);
    expect(find.textContaining('音源尚未通过校验'), findsOneWidget);
  });

  testWidgets('offset cannot turn alignment into negative stored time', (tester) async {
    await open(tester, source: proposed, offset: const Duration(seconds: 2));
    await showTiming(tester);
    expect(tester.widget<CheckboxListTile>(timing()).onChanged, isNull);
  });

  testWidgets('green-only action never includes the selected alignment', (tester) async {
    await open(tester, verdict: LyricProofreadReviewVerdict.green);
    await showTiming(tester);
    await tester.tap(timing());
    await tester.pumpAndSettle();
    await tester.tap(find.text('仅应用绿色（1）'));
    await tester.pumpAndSettle();
    expect(selected!.acceptedProposalIndices, {0});
    expect(selected!.acceptedReferenceTimingIndices, isEmpty);
  });

  for (final size in [const Size(320, 568), const Size(800, 480)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('timing checkbox has accessible semantics at $size scale $scale', (tester) async {
        final semantics = tester.ensureSemantics();
        await open(tester, source: proposed, size: size, scale: scale);
        await showTiming(tester);
        expect(find.bySemanticsLabel(RegExp('采纳此行参考对齐时间')), findsWidgets);
        expect(tester.widget<CheckboxListTile>(timing()).value, isFalse);
        expect(tester.takeException(), isNull);
        semantics.dispose();
      });
    }
  }
}

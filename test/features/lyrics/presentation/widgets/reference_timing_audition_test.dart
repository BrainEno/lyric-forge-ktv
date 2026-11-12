import 'dart:async';

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
  const planner = ReferenceForcedAlignmentPlanner();
  final prepared = planner.prepare(const ReferenceLyricInput(lines: [ReferenceLyricLine(text: 'reference')], timed: false, format: 'txt')).prepared!;
  final evidence = planner.plan(reference: prepared, spans: const [ForcedAlignedSpan(text: 'reference', start: Duration(seconds: 2), end: Duration(seconds: 3))], audioDuration: const Duration(seconds: 10)).proposals.single;
  const original = LyricLine(id: 'line', text: 'original', startTime: Duration.zero, endTime: Duration(seconds: 1));
  const proposal = LyricLine(id: 'line', text: 'reference', startTime: Duration.zero, endTime: Duration(seconds: 1));
  LyricProofreadV2Selection? selection;

  Future<void> open(WidgetTester tester, {
    ReferenceTimingPreview? preview,
    LyricProofreadReviewVerdict verdict = LyricProofreadReviewVerdict.amber,
    LyricLine? source = original,
    Size size = const Size(1000, 700),
    double scale = 1,
  }) async {
    selection = null;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
      home: Scaffold(body: Builder(builder: (context) => TextButton(
        onPressed: () async {
          selection = await showLyricProofreadV2ReviewDialog(context,
            summary: 'summary', explanation: 'evidence', onPreviewDraftLine: null,
            allowReferenceTimingSelection: true, onPreviewReferenceTiming: preview,
            originalGlobalOffset: const Duration(seconds: 1),
            items: [LyricProofreadV2ReviewItem(proposalIndex: 7, sourceIndex: source == null ? null : 0, originalLine: source, proposedLine: proposal, verdict: verdict, referenceTimingEvidence: evidence)],
            droppedItems: const [],
          );
        },
        child: const Text('open'),
      ))),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder button() => find.byKey(const ValueKey('preview_reference_timing_7'));
  Future<void> showButton(WidgetTester tester) async {
    await tester.scrollUntilVisible(button(), 100, scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)));
    await tester.pumpAndSettle();
  }

  testWidgets('preview sends the raw absolute evidence, not adjusted proposal times', (tester) async {
    int? proposalIndex;
    int? sourceIndex;
    ReferenceForcedTimingProposal? sent;
    await open(tester, preview: (proposal, source, timing) async {
      proposalIndex = proposal;
      sourceIndex = source;
      sent = timing;
      return const ProofreadTimedLinePreviewResult.success();
    });
    await showButton(tester);
    await tester.tap(button());
    await tester.pumpAndSettle();
    expect(proposalIndex, 7);
    expect(sourceIndex, 0);
    expect(sent!.start, const Duration(seconds: 2));
    expect(sent!.end, const Duration(seconds: 3));
    expect(find.textContaining('正在试听参考对齐时间'), findsOneWidget);
    expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('accept_reference_timing_7'))).value, isFalse);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(selection, isNull);
  });

  testWidgets('preview works on protected and newly inserted rows without accepting them', (tester) async {
    final sources = <int?>[];
    Future<ProofreadTimedLinePreviewResult> preview(int _, int? source, ReferenceForcedTimingProposal timing) async {
      sources.add(source);
      return const ProofreadTimedLinePreviewResult.success();
    }
    await open(tester, preview: preview, verdict: LyricProofreadReviewVerdict.locked);
    await showButton(tester);
    await tester.tap(button());
    await tester.pumpAndSettle();
    expect(sources, [0]);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await open(tester, preview: preview, source: null);
    await showButton(tester);
    await tester.tap(button());
    await tester.pumpAndSettle();
    expect(sources, [0, null]);
  });

  testWidgets('unverified audio disables audition but leaves evidence readable', (tester) async {
    await open(tester);
    await showButton(tester);
    expect(tester.widget<TextButton>(button()).onPressed, isNull);
    expect(find.textContaining('音源未通过校验'), findsOneWidget);
    expect(find.textContaining('对齐时间（绝对音频时间）'), findsOneWidget);
  });

  testWidgets('playback failure is shown without changing the selection', (tester) async {
    await open(tester, preview: (_, __, ___) async => const ProofreadTimedLinePreviewResult.failure('音源不匹配'));
    await showButton(tester);
    await tester.tap(button());
    await tester.pumpAndSettle();
    expect(find.text('试听失败：音源不匹配'), findsOneWidget);
    expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('accept_reference_timing_7'))).value, isFalse);
  });

  testWidgets('unexpected preview errors are reported rather than crashing dialog', (tester) async {
    await open(tester, preview: (_, __, ___) async => throw StateError('test failure'));
    await showButton(tester);
    await tester.tap(button());
    await tester.pumpAndSettle();
    expect(find.textContaining('试听失败：Bad state: test failure'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending preview disables repeated clicks and recovers afterward', (tester) async {
    final gate = Completer<ProofreadTimedLinePreviewResult>();
    var calls = 0;
    await open(tester, preview: (_, __, ___) { calls++; return gate.future; });
    await showButton(tester);
    await tester.tap(button());
    await tester.pump();
    expect(tester.widget<TextButton>(button()).onPressed, isNull);
    expect(find.text('正在检查音源…'), findsOneWidget);
    expect(calls, 1);
    gate.complete(const ProofreadTimedLinePreviewResult.success(message: '已暂停试听。'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(button()).onPressed, isNotNull);
    expect(find.text('已暂停试听。'), findsOneWidget);
  });

  testWidgets('late preview completion after dialog closes does not set disposed state', (tester) async {
    final gate = Completer<ProofreadTimedLinePreviewResult>();
    await open(tester, preview: (_, __, ___) => gate.future);
    await showButton(tester);
    await tester.tap(button());
    await tester.pump();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    gate.complete(const ProofreadTimedLinePreviewResult.success());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(selection, isNull);
  });

  for (final size in [const Size(320, 568), const Size(800, 480)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('preview control remains accessible at $size scale $scale', (tester) async {
        final semantics = tester.ensureSemantics();
        await open(tester, size: size, scale: scale, preview: (_, __, ___) async => const ProofreadTimedLinePreviewResult.success());
        await showButton(tester);
        expect(find.bySemanticsLabel(RegExp('试听参考对齐时间')), findsWidgets);
        expect(tester.widget<TextButton>(button()).onPressed, isNotNull);
        expect(tester.takeException(), isNull);
        semantics.dispose();
      });
    }
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/reference_lyric_input.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/reference_lyric_line.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/forced_alignment_proofread_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/proofread_review_proposal.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/reference_forced_alignment_planner.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/lyric_review_strings.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_proofread_v2_dialog.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

void main() {
  final prepared = const ReferenceForcedAlignmentPlanner()
      .prepare(
        const ReferenceLyricInput(
          lines: [ReferenceLyricLine(text: 'Reference lyric')],
          timed: false,
          format: 'txt',
        ),
      )
      .prepared!;
  final plan = const ReferenceForcedAlignmentPlanner().plan(
    reference: prepared,
    spans: const [
      ForcedAlignedSpan(
        text: 'Reference lyric',
        start: Duration(milliseconds: 500),
        end: Duration(milliseconds: 1500),
      ),
    ],
    audioDuration: const Duration(seconds: 3),
  );
  const original = LyricLine(
    text: 'Protected lyric',
    startTime: Duration.zero,
    endTime: Duration(seconds: 2),
  );

  for (final size in [const Size(320, 568), const Size(800, 480)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'read-only reference timing is visible at $size scale $scale',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final semantics = tester.ensureSemantics();
          var closed = false;
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
                    onPressed: () async {
                      await showLyricProofreadV2ReviewDialog(
                        context,
                        summary: '参考歌词优先',
                        explanation:
                            LyricReviewStrings.referenceAlignmentSummary(plan),
                        items: [
                          LyricProofreadV2ReviewItem(
                            proposalIndex: 0,
                            sourceIndex: 0,
                            originalLine: original,
                            proposedLine: original,
                            verdict: LyricProofreadReviewVerdict.locked,
                            referenceTimingEvidence: plan.proposals.single,
                          ),
                        ],
                        droppedItems: const [],
                        onPreviewDraftLine: null,
                      );
                      closed = true;
                    },
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();
          final source = find.byKey(
            const ValueKey('reference_alignment_source_0'),
          );
          await tester.scrollUntilVisible(
            source,
            100,
            scrollable: find.descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.textContaining('forcedAlignment(reference)'),
            findsOneWidget,
          );
          expect(find.text('对齐文本：Reference lyric'), findsOneWidget);
          expect(
            find.textContaining('对齐时间（绝对音频时间）：0.50 s – 1.50 s'),
            findsOneWidget,
          );
          expect(find.textContaining('音源尚未通过校验，暂不可采纳'), findsOneWidget);
          expect(
            find.bySemanticsLabel(RegExp('forcedAlignment\\(reference\\)')),
            findsWidgets,
          );
          expect(find.text('取消').hitTestable(), findsOneWidget);
          await tester.tap(find.text('取消'));
          await tester.pumpAndSettle();
          expect(closed, isTrue);
          expect(tester.takeException(), isNull);
          semantics.dispose();
        },
      );
    }
  }
}

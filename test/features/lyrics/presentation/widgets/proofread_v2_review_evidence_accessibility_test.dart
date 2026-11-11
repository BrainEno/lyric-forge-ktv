import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/proofread_review_proposal.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_proofread_v2_dialog.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

void main() {
  for (final size in [const Size(320, 568), const Size(800, 480)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'long evidence explanation and proposal remain scrollable at $size scale $scale',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
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
                        summary:
                            '策略：参考歌词优先 · 参考覆盖率 100% · 绿色 1 · 琥珀色 0 · 受保护 0 · 灰色 0',
                        explanation:
                            '自动策略计算参考文本覆盖率 100%。参考优先会以参考行组织提案；低置信、歧义、插值时间和结构差异保持琥珀色。本次选择了参考歌词优先，ForcedAligner 未运行；参考优先暂不支持强制对齐。本次选择了参考歌词优先，第二份 ASR 转写稿未参与本次复核。',
                        items: [
                          LyricProofreadV2ReviewItem(
                            proposalIndex: 0,
                            sourceIndex: 0,
                            originalLine: const LyricLine(
                              text: 'old text',
                              startTime: Duration.zero,
                              endTime: Duration(seconds: 1),
                            ),
                            proposedLine: const LyricLine(
                              text: 'new text',
                              startTime: Duration.zero,
                              endTime: Duration(seconds: 1),
                            ),
                            verdict: LyricProofreadReviewVerdict.green,
                          ),
                        ],
                        droppedItems: const [],
                        onPreviewDraftLine: null,
                      );
                      closed = true;
                    },
                    child: const Text('open review'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('open review'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final explanation = find.textContaining('ForcedAligner 未运行');
          await tester.scrollUntilVisible(
            explanation,
            100,
            scrollable: find.descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            ),
          );
          expect(tester.getRect(explanation).overlaps(tester.getRect(find.byType(ListView))), isTrue);
          final card = find.byKey(const ValueKey('proofread_proposal_0'));
          await tester.scrollUntilVisible(
            card,
            180,
            scrollable: find.descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.getRect(card).overlaps(tester.getRect(find.byType(ListView))), isTrue);
          expect(find.text('取消').hitTestable(), findsOneWidget);
          await tester.tap(find.text('取消'));
          await tester.pumpAndSettle();
          expect(closed, isTrue);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

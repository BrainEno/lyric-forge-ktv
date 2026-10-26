import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/proofread_strategy_selector.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/proofread_result.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_proofread_v2_dialog.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

void main() {
  LyricLine line(
    String text, {
    int startMs = 0,
    int endMs = 1000,
    String? id,
  }) {
    return LyricLine(
      text: text,
      startTime: Duration(milliseconds: startMs),
      endTime: Duration(milliseconds: endMs),
      id: id,
    );
  }

  Widget host(Widget child) => MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(body: Center(child: child)),
      );

  testWidgets('strategy dialog returns reference-first with reference enabled',
      (tester) async {
    ProofreadV2RunOptions? result;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await showProofreadV2RunOptionsDialog(context);
            },
            child: const Text('open strategy'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open strategy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('参考歌词优先'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.strategy, LyricSourceStrategy.referenceFirst);
    expect(result!.useReference, isTrue);
  });

  testWidgets('ASR-first options return the optional timestamped secondary transcript',
      (tester) async {
    ProofreadV2RunOptions? result;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await showProofreadV2RunOptionsDialog(context);
            },
            child: const Text('open strategy'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open strategy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ASR 优先'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('secondary_asr_transcript_input')),
      '[00:01.00] first line\n[00:02.00] second line',
    );
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.strategy, LyricSourceStrategy.asrFirst);
    expect(
      result!.secondaryTranscriptText,
      '[00:01.00] first line\n[00:02.00] second line',
    );
  });

  testWidgets('ASR-first options can enable ForcedAligner evidence',
      (tester) async {
    ProofreadV2RunOptions? result;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await showProofreadV2RunOptionsDialog(context);
            },
            child: const Text('open strategy'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open strategy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ASR 优先'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('forced_alignment_review_toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.useForcedAlignment, isTrue);
  });

  testWidgets('review dialog exposes token timing and can audition one word',
      (tester) async {
    final token = TimedLyricToken(
      text: 'hello',
      interval: ProofreadTimeInterval(
        start: const Duration(milliseconds: 200),
        end: const Duration(milliseconds: 600),
      ),
      confidence: 35,
      source: ProofreadTimeSource.forcedAligner,
    );
    int? auditionedLineIndex;
    TimedLyricToken? auditionedToken;

    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              await showLyricProofreadV2ReviewDialog(
                context,
                summary: '绿色 0 · 琥珀色 1',
                explanation: '词级时间仅供复核。',
                items: [
                  LyricProofreadV2ReviewItem(
                    proposalIndex: 0,
                    sourceIndex: 0,
                    originalLine: line('hello world'),
                    proposedLine: line('hello world'),
                    verdict: LyricProofreadReviewVerdict.amber,
                    reasonLabel: '词级对齐证据',
                    alignmentTokens: [
                      token,
                      TimedLyricToken(
                        text: 'world',
                        interval: ProofreadTimeInterval(
                          start: const Duration(milliseconds: 650),
                          end: const Duration(milliseconds: 900),
                        ),
                        confidence: null,
                        source: ProofreadTimeSource.forcedAligner,
                      ),
                    ],
                  ),
                ],
                droppedItems: const [],
                onPreviewDraftLine: null,
                onPreviewAlignmentToken: (index, value) {
                  auditionedLineIndex = index;
                  auditionedToken = value;
                },
              );
            },
            child: const Text('open token review'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open token review'));
    await tester.pumpAndSettle();
    expect(find.text('词级时间证据（2 词）'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('alignment_tokens_0')));
    await tester.pumpAndSettle();

    expect(find.text('hello'), findsOneWidget);
    expect(find.text('0.20 s – 0.60 s · 置信度 35%'), findsOneWidget);
    expect(find.text('置信度未提供'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('alignment_token_0_0')),
    );
    await tester.pumpAndSettle();

    expect(auditionedLineIndex, 0);
    expect(auditionedToken, same(token));
    expect(tester.takeException(), isNull);
  });

  testWidgets('review dialog stays within a compact phone viewport',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              await showLyricProofreadV2ReviewDialog(
                context,
                summary: '策略：参考歌词优先 · 绿色 1',
                explanation: '逐行查看原文与建议。',
                items: [
                  LyricProofreadV2ReviewItem(
                    proposalIndex: 0,
                    sourceIndex: 0,
                    originalLine: line('This is a long original lyric line that wraps on a phone'),
                    proposedLine: line('This is the reviewed lyric line that wraps on a phone'),
                    verdict: LyricProofreadReviewVerdict.green,
                    reasonLabel: '高置信度参考匹配',
                  ),
                ],
                droppedItems: const [],
                onPreviewDraftLine: null,
              );
            },
            child: const Text('open compact review'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open compact review'));
    await tester.pumpAndSettle();

    expect(find.textContaining('建议：This is the reviewed lyric line'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('review dialog compares rows and returns amber plus grey restore',
      (tester) async {
    LyricProofreadV2Selection? result;
    final items = [
      LyricProofreadV2ReviewItem(
        proposalIndex: 0,
        sourceIndex: 0,
        originalLine: line('old green', id: 'green'),
        proposedLine: line('corrected green', id: 'green'),
        verdict: LyricProofreadReviewVerdict.green,
        reasonLabel: '高置信度参考匹配',
      ),
      LyricProofreadV2ReviewItem(
        proposalIndex: 1,
        sourceIndex: 1,
        originalLine: line('old amber', startMs: 1100, endMs: 2000, id: 'amber'),
        proposedLine: line(
          'proposed amber',
          startMs: 1200,
          endMs: 2100,
          id: 'amber',
        ),
        verdict: LyricProofreadReviewVerdict.amber,
        reasonLabel: '对齐存在歧义',
      ),
      LyricProofreadV2ReviewItem(
        proposalIndex: 2,
        sourceIndex: 3,
        originalLine: line('protected row', startMs: 2200, endMs: 3000, id: 'locked'),
        proposedLine: line('protected row', startMs: 2200, endMs: 3000, id: 'locked'),
        verdict: LyricProofreadReviewVerdict.locked,
        reasonLabel: '手动编辑保护',
      ),
    ];
    final dropped = [
      LyricProofreadV2DroppedItem(
        sourceIndex: 2,
        line: line('restore me', startMs: 2100, endMs: 2150, id: 'drop'),
        reasonLabel: '未找到可靠匹配',
      ),
    ];

    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await showLyricProofreadV2ReviewDialog(
                context,
                summary: '绿色 1 · 琥珀色 1 · 受保护 1 · 灰色 1',
                explanation: '低置信提案需要人工确认。',
                items: items,
                droppedItems: dropped,
                onPreviewDraftLine: null,
              );
            },
            child: const Text('open review'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open review'));
    await tester.pumpAndSettle();
    expect(find.text('原文：old green'), findsOneWidget);
    expect(find.text('建议：corrected green'), findsOneWidget);
    expect(find.textContaining('琥珀色 · 逐行复核'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('accept_amber_1')));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.textContaining('restore me'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('restore_dropped_2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用所选（绿色 + 琥珀色 1）'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.acceptedProposalIndices, containsAll(<int>{0, 1, 2}));
    expect(result!.restoredDraftIndices, contains(2));
  });

  testWidgets('green-only action ignores amber selection and grey restoration',
      (tester) async {
    LyricProofreadV2Selection? result;
    final items = [
      LyricProofreadV2ReviewItem(
        proposalIndex: 0,
        sourceIndex: 0,
        originalLine: line('before', id: 'green'),
        proposedLine: line('after', id: 'green'),
        verdict: LyricProofreadReviewVerdict.green,
        reasonLabel: '参考时间戳',
      ),
      LyricProofreadV2ReviewItem(
        proposalIndex: 1,
        sourceIndex: 1,
        originalLine: line('old amber', startMs: 1100, endMs: 2000, id: 'amber'),
        proposedLine: line('new amber', startMs: 1100, endMs: 2000, id: 'amber'),
        verdict: LyricProofreadReviewVerdict.amber,
        reasonLabel: '对齐存在歧义',
      ),
      LyricProofreadV2ReviewItem(
        proposalIndex: 2,
        sourceIndex: 2,
        originalLine: line(
          'protected row',
          startMs: 2100,
          endMs: 3000,
          id: 'locked',
        ),
        proposedLine: line(
          'protected row',
          startMs: 2100,
          endMs: 3000,
          id: 'locked',
        ),
        verdict: LyricProofreadReviewVerdict.locked,
        reasonLabel: '手动编辑保护',
      ),
    ];
    final dropped = [
      LyricProofreadV2DroppedItem(
        sourceIndex: 3,
        line: line(
          'restore separately',
          startMs: 3100,
          endMs: 4000,
          id: 'drop',
        ),
        reasonLabel: '未找到可靠匹配',
      ),
    ];

    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await showLyricProofreadV2ReviewDialog(
                context,
                summary: '绿色 1 · 琥珀色 1 · 受保护 1 · 灰色 1',
                explanation: '逐项复核。',
                items: items,
                droppedItems: dropped,
                onPreviewDraftLine: null,
              );
            },
            child: const Text('open review'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open review'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('accept_amber_1')));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('restore_dropped_3')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('仅应用绿色（1）'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.acceptedProposalIndices, contains(0));
    expect(result!.acceptedProposalIndices, contains(2));
    expect(result!.acceptedProposalIndices, isNot(contains(1)));
    expect(result!.restoredDraftIndices, isEmpty);
  });

  testWidgets('review cancel returns no acceptance selection', (tester) async {
    LyricProofreadV2Selection? result;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await showLyricProofreadV2ReviewDialog(
                context,
                summary: '绿色 1',
                explanation: '取消后不采纳任何提案。',
                items: [
                  LyricProofreadV2ReviewItem(
                    proposalIndex: 0,
                    sourceIndex: 0,
                    originalLine: line('before', id: 'line'),
                    proposedLine: line('after', id: 'line'),
                    verdict: LyricProofreadReviewVerdict.green,
                    reasonLabel: '参考时间戳',
                  ),
                ],
                droppedItems: const [],
                onPreviewDraftLine: null,
              );
            },
            child: const Text('open cancel review'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open cancel review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });
}

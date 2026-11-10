import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/proofread_strategy_selector.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/proofread_result.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/proofread_review_proposal.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/lyric_review_strings.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_proofread_v2_dialog.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

void main() {
  LyricLine line(String text, {int startMs = 0, int endMs = 1000, String? id}) {
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

  testWidgets(
    'strategy dialog returns reference-first with reference enabled',
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
    },
  );

  testWidgets(
    'ASR-first options return the optional timestamped secondary transcript',
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
    },
  );

  testWidgets('ASR-first options can enable ForcedAligner evidence', (
    tester,
  ) async {
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
    await tester.tap(
      find.byKey(const ValueKey('forced_alignment_review_toggle')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.useForcedAlignment, isTrue);
  });

  for (final example in <(String, String, String, String)>[
    ('你好🙂', '你好🌙', '🙂', '🌙'),
    ('我等你', '我在等你', '', '在'),
    ('我在等你', '我等你', '在', ''),
    ('原文', '', '原文', ''),
  ]) {
    testWidgets('review highlights text changes $example', (tester) async {
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => FilledButton(
              onPressed: () => showLyricProofreadV2ReviewDialog(
                context,
                summary: '琥珀色 1',
                explanation: '复核差异',
                items: [
                  LyricProofreadV2ReviewItem(
                    proposalIndex: 0,
                    sourceIndex: 0,
                    originalLine: line(example.$1),
                    proposedLine: line(example.$2),
                    verdict: LyricProofreadReviewVerdict.amber,
                  ),
                ],
                droppedItems: const [],
                onPreviewDraftLine: null,
              ),
              child: const Text('open diff'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open diff'));
      await tester.pumpAndSettle();

      for (final side in <(String, String, String)>[
        ('original', '原文：${example.$1}', example.$3),
        ('proposed', '建议：${example.$2}', example.$4),
      ]) {
        final widget = tester.widget<Text>(
          find.byKey(ValueKey('proofread_${side.$1}_diff_0')),
        );
        final root = widget.textSpan! as TextSpan;
        expect(root.toPlainText(), side.$2);
        final highlighted = root.children!
            .cast<TextSpan>()
            .where((span) => span.style?.decoration == TextDecoration.underline)
            .map((span) => span.text)
            .join();
        expect(highlighted, side.$3);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('timing-only changes and inserted rows retain plain text', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => FilledButton(
            onPressed: () => showLyricProofreadV2ReviewDialog(
              context,
              summary: '琥珀色 2',
              explanation: '复核',
              items: [
                LyricProofreadV2ReviewItem(
                  proposalIndex: 0,
                  sourceIndex: 0,
                  originalLine: line('same'),
                  proposedLine: line('same', startMs: 100),
                  verdict: LyricProofreadReviewVerdict.amber,
                ),
                LyricProofreadV2ReviewItem(
                  proposalIndex: 1,
                  sourceIndex: null,
                  originalLine: null,
                  proposedLine: line('新增歌词'),
                  verdict: LyricProofreadReviewVerdict.amber,
                ),
              ],
              droppedItems: const [],
              onPreviewDraftLine: null,
            ),
            child: const Text('open unchanged'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open unchanged'));
    await tester.pumpAndSettle();
    expect(find.text('原文：same'), findsOneWidget);
    expect(find.text('建议：same'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('proofread_original_diff_0')),
      findsNothing,
    );
    await tester.drag(find.byType(ListView), const Offset(0, -250));
    await tester.pumpAndSettle();
    expect(find.text('原文：无（这是待插入的参考行）'), findsOneWidget);
    expect(find.text('建议：新增歌词'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('review dialog exposes token timing and can audition one word', (
    tester,
  ) async {
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
                    alignmentHints: {
                      LyricProofreadV2AlignmentHint.wordTimingAvailable,
                    },
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
    expect(find.text('依据：词级对齐 2 词'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('alignment_tokens_0')));
    await tester.pumpAndSettle();

    expect(find.text('hello'), findsOneWidget);
    expect(find.text('0.20 s – 0.60 s · 置信度 35%'), findsOneWidget);
    expect(find.text('0.65 s – 0.90 s · 置信度未提供'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('alignment_token_0_0')));
    await tester.pumpAndSettle();

    expect(auditionedLineIndex, 0);
    expect(auditionedToken, same(token));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'review dialog previews original and proposed timing with visible feedback',
    (tester) async {
      final original = line('original words', startMs: 1000, endMs: 2400);
      final proposed = line('proposed words', startMs: 1500, endMs: 2900);
      final calls = <(int, LyricLine, Duration)>[];

      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                await showLyricProofreadV2ReviewDialog(
                  context,
                  summary: '绿色 0 · 琥珀色 1',
                  explanation: '时间复核。',
                  items: [
                    LyricProofreadV2ReviewItem(
                      proposalIndex: 0,
                      sourceIndex: 0,
                      originalLine: original,
                      proposedLine: proposed,
                      verdict: LyricProofreadReviewVerdict.amber,
                    ),
                  ],
                  droppedItems: const [],
                  onPreviewDraftLine: null,
                  originalGlobalOffset: const Duration(milliseconds: 200),
                  proposedGlobalOffset: Duration.zero,
                  onPreviewTimedLine: (index, lyricLine, offset) async {
                    calls.add((index, lyricLine, offset));
                    return lyricLine.text == 'proposed words'
                        ? const ProofreadTimedLinePreviewResult.failure(
                            '本地音频不可用',
                          )
                        : const ProofreadTimedLinePreviewResult.success();
                  },
                );
              },
              child: const Text('open timed review'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open timed review'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('preview_original_0')));
      await tester.pumpAndSettle();
      expect(calls, hasLength(1));
      expect(calls.first.$1, 0);
      expect(calls.first.$2, same(original));
      expect(calls.first.$3, const Duration(milliseconds: 200));
      expect(find.text('正在试听原始时间范围；再次点击可暂停。'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('preview_proposed_0')));
      await tester.pumpAndSettle();
      expect(calls, hasLength(2));
      expect(calls.last.$2, same(proposed));
      expect(calls.last.$3, Duration.zero);
      expect(find.text('试听失败：本地音频不可用'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('review dialog stays within a compact phone viewport', (
    tester,
  ) async {
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
                    originalLine: line(
                      'This is a long original lyric line that wraps on a phone',
                    ),
                    proposedLine: line(
                      'This is the reviewed lyric line that wraps on a phone',
                    ),
                    verdict: LyricProofreadReviewVerdict.green,
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

    expect(
      find.byKey(const ValueKey('proofread_proposed_diff_0')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'review dialog compares rows and returns amber plus grey restore',
    (tester) async {
      LyricProofreadV2Selection? result;
      final items = [
        LyricProofreadV2ReviewItem(
          proposalIndex: 0,
          sourceIndex: 0,
          originalLine: line('old green', id: 'green'),
          proposedLine: line('corrected green', id: 'green'),
          verdict: LyricProofreadReviewVerdict.green,
          proofreadReasons: {ProofreadReason.referenceCorrection},
        ),
        LyricProofreadV2ReviewItem(
          proposalIndex: 1,
          sourceIndex: 1,
          originalLine: line(
            'old amber',
            startMs: 1100,
            endMs: 2000,
            id: 'amber',
          ),
          proposedLine: line(
            'proposed amber',
            startMs: 1200,
            endMs: 2100,
            id: 'amber',
          ),
          verdict: LyricProofreadReviewVerdict.amber,
          referenceReasons: {
            LyricProofreadV2ReferenceReason.ambiguousAlignment,
          },
        ),
        LyricProofreadV2ReviewItem(
          proposalIndex: 2,
          sourceIndex: 3,
          originalLine: line(
            'protected row',
            startMs: 2200,
            endMs: 3000,
            id: 'locked',
          ),
          proposedLine: line(
            'protected row',
            startMs: 2200,
            endMs: 3000,
            id: 'locked',
          ),
          verdict: LyricProofreadReviewVerdict.locked,
          referenceReasons: {LyricProofreadV2ReferenceReason.protectedLine},
        ),
      ];
      final dropped = [
        LyricProofreadV2DroppedItem(
          sourceIndex: 2,
          line: line('restore me', startMs: 2100, endMs: 2150, id: 'drop'),
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
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('proofread_original_diff_0')),
            )
            .textSpan!
            .toPlainText(),
        '原文：old green',
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('proofread_proposed_diff_0')),
            )
            .textSpan!
            .toPlainText(),
        '建议：corrected green',
      );
      expect(find.text('依据：参考文本纠正'), findsOneWidget);
      expect(find.textContaining('琥珀色 · 逐行复核'), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(find.text('依据：对齐存在歧义'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('accept_amber_1')));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(find.textContaining('restore me'), findsOneWidget);
      expect(
        find.textContaining(LyricReviewStrings.droppedReferenceItemReason),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('restore_dropped_2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('应用所选（绿色 + 琥珀色 1）'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.acceptedProposalIndices, containsAll(<int>{0, 1, 2}));
      expect(result!.restoredDraftIndices, contains(2));
    },
  );

  testWidgets(
    'green-only action ignores amber selection and grey restoration',
    (tester) async {
      LyricProofreadV2Selection? result;
      final items = [
        LyricProofreadV2ReviewItem(
          proposalIndex: 0,
          sourceIndex: 0,
          originalLine: line('before', id: 'green'),
          proposedLine: line('after', id: 'green'),
          verdict: LyricProofreadReviewVerdict.green,
          referenceReasons: {
            LyricProofreadV2ReferenceReason.referenceTimestamp,
          },
        ),
        LyricProofreadV2ReviewItem(
          proposalIndex: 1,
          sourceIndex: 1,
          originalLine: line(
            'old amber',
            startMs: 1100,
            endMs: 2000,
            id: 'amber',
          ),
          proposedLine: line(
            'new amber',
            startMs: 1100,
            endMs: 2000,
            id: 'amber',
          ),
          verdict: LyricProofreadReviewVerdict.amber,
          referenceReasons: {
            LyricProofreadV2ReferenceReason.ambiguousAlignment,
          },
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
          referenceReasons: {LyricProofreadV2ReferenceReason.protectedLine},
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
    },
  );

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
                    referenceReasons: {
                      LyricProofreadV2ReferenceReason.referenceTimestamp,
                    },
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
  testWidgets('shows ForcedAligner coverage diagnostics in the review UI', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              await showLyricProofreadV2ReviewDialog(
                context,
                summary: '策略：ASR 优先',
                explanation: '低覆盖率证据需要人工复核。',
                items: const [],
                droppedItems: const [],
                onPreviewDraftLine: null,
                alignmentDiagnostics: ProofreadAlignmentDiagnostics(
                  totalLineCount: 3,
                  matchedLineCount: 2,
                  skippedSpanCount: 1,
                  unmatchedLineIndices: [1],
                ),
              );
            },
            child: const Text('open diagnostics review'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open diagnostics review'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('forced_alignment_diagnostics')),
      findsOneWidget,
    );
    expect(find.text('ForcedAligner 覆盖：2/3 行（67%）'), findsOneWidget);
    expect(find.text('未分配对齐片段：1（需要人工判定）'), findsOneWidget);
    expect(find.text('未匹配歌词行：2'), findsOneWidget);
    expect(find.text('词级时间仅供人工复核；不自动修改歌词行级时间戳。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

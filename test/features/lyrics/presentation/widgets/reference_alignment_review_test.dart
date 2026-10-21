import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/reference_lyric_input.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/reference_lyric_line.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_alignment_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/reference_alignment_review.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

void main() {
  const alignmentService = LyricAlignmentService();

  LyricDocument buildDocument() {
    return const LyricDocument(
      language: 'zh',
      lines: [
        LyricLine(
          text: '月亮代表我的星',
          startTime: Duration(seconds: 1),
          endTime: Duration(seconds: 5),
        ),
        LyricLine(
          text: '第二句错',
          startTime: Duration(seconds: 5),
          endTime: Duration(seconds: 9),
        ),
      ],
    );
  }

  ReferenceLyricInput buildInput() {
    return const ReferenceLyricInput(
      lines: [
        ReferenceLyricLine(text: '月亮代表我的心'),
        ReferenceLyricLine(text: '第二句对'),
      ],
      timed: false,
      format: 'txt',
    );
  }

  Future<void> pumpReview(
    WidgetTester tester, {
    required LyricDocument document,
    required LyricAlignmentResult alignment,
    required ReferenceLyricInput input,
    required Set<int> manuallyEditedLineIndices,
    required void Function(ReferenceAlignmentReviewDecision?) onResult,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final decision = await showReferenceAlignmentReview(
                  context,
                  document: document,
                  alignment: alignment,
                  input: input,
                  manuallyEditedLineIndices: manuallyEditedLineIndices,
                  timingUnavailableReason: null,
                );
                onResult(decision);
              },
              child: const Text('打开逐行确认'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开逐行确认'));
    await tester.pumpAndSettle();
  }

  testWidgets('默认勾选高置信行，低相似行保持跳过', (tester) async {
    final document = buildDocument();
    final input = buildInput();
    final alignment = alignmentService.align(
      document: document,
      referenceLines: input.lines,
    );
    ReferenceAlignmentReviewDecision? decision;

    await pumpReview(
      tester,
      document: document,
      alignment: alignment,
      input: input,
      manuallyEditedLineIndices: const {},
      onResult: (value) => decision = value,
    );

    expect(find.text('逐行确认参考歌词'), findsOneWidget);
    expect(find.text('低相似'), findsOneWidget);

    final checkboxes = tester
        .widgetList<Checkbox>(find.byType(Checkbox))
        .toList();
    expect(checkboxes, hasLength(2));
    expect(checkboxes[0].value, isTrue);
    expect(checkboxes[1].value, isFalse);

    await tester.tap(find.text('应用 1 行修正'));
    await tester.pumpAndSettle();

    expect(decision, isNotNull);
    expect(decision!.acceptedReferenceIndices, {0});
    expect(decision!.overriddenAsrLineIndices, isEmpty);
    expect(decision!.applyReferenceTiming, isFalse);
  });

  testWidgets('手动编辑行默认锁定，显式确认后才可替换', (tester) async {
    final document = buildDocument();
    final input = buildInput();
    final alignment = alignmentService.align(
      document: document,
      referenceLines: input.lines,
    );
    ReferenceAlignmentReviewDecision? decision;

    await pumpReview(
      tester,
      document: document,
      alignment: alignment,
      input: input,
      manuallyEditedLineIndices: const {0},
      onResult: (value) => decision = value,
    );

    expect(find.text('本次已手动编辑，默认不覆盖'), findsOneWidget);
    expect(find.byType(Checkbox), findsOneWidget);
    expect(find.text('没有可应用的修改'), findsOneWidget);

    await tester.tap(find.text('仍要替换'));
    await tester.pumpAndSettle();
    expect(find.text('仍然替换这一行？'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '仍要替换'));
    await tester.pumpAndSettle();

    expect(find.text('本次已手动编辑，默认不覆盖'), findsNothing);
    expect(find.byType(Checkbox), findsNWidgets(2));
    expect(find.text('已选 1 行'), findsOneWidget);

    await tester.tap(find.text('应用 1 行修正'));
    await tester.pumpAndSettle();

    expect(decision, isNotNull);
    expect(decision!.acceptedReferenceIndices, {0});
    expect(decision!.overriddenAsrLineIndices, {0});
  });

  testWidgets('非歧义漏行默认勾选并随确认返回', (tester) async {
    const document = LyricDocument(
      language: 'zh',
      lines: [
        LyricLine(
          text: '第一句歌词',
          startTime: Duration.zero,
          endTime: Duration(seconds: 4),
        ),
        LyricLine(
          text: '第三句歌词',
          startTime: Duration(seconds: 8),
          endTime: Duration(seconds: 12),
        ),
      ],
    );
    const input = ReferenceLyricInput(
      lines: [
        ReferenceLyricLine(text: '第一句歌词'),
        ReferenceLyricLine(text: '第二句歌词'),
        ReferenceLyricLine(text: '第三句歌词'),
      ],
      timed: false,
      format: 'txt',
    );
    final alignment = alignmentService.align(
      document: document,
      referenceLines: input.lines,
    );
    ReferenceAlignmentReviewDecision? decision;

    await pumpReview(
      tester,
      document: document,
      alignment: alignment,
      input: input,
      manuallyEditedLineIndices: const {},
      onResult: (value) => decision = value,
    );

    expect(find.text('补全漏行：参考有、草稿无（1）'), findsOneWidget);
    expect(find.text('插入到第 2 行前'), findsOneWidget);
    final checkboxes = tester
        .widgetList<Checkbox>(find.byType(Checkbox))
        .toList();
    expect(checkboxes, hasLength(1));
    expect(checkboxes.single.value, isTrue);

    await tester.tap(find.widgetWithText(FilledButton, '补全 1 行'));
    await tester.pumpAndSettle();

    expect(decision, isNotNull);
    expect(decision!.acceptedMissingReferenceIndices, {1});
    expect(decision!.acceptedReferenceIndices, isEmpty);
  });

  testWidgets('可能被合并的漏行默认不勾选，手动确认后才返回', (tester) async {
    const document = LyricDocument(
      language: 'zh',
      lines: [
        LyricLine(
          text: '第一句歌词',
          startTime: Duration.zero,
          endTime: Duration(seconds: 4),
        ),
        LyricLine(
          text: '完全无关的幻觉行',
          startTime: Duration(seconds: 4),
          endTime: Duration(seconds: 8),
        ),
        LyricLine(
          text: '第三句歌词',
          startTime: Duration(seconds: 8),
          endTime: Duration(seconds: 12),
        ),
      ],
    );
    const input = ReferenceLyricInput(
      lines: [
        ReferenceLyricLine(text: '第一句歌词'),
        ReferenceLyricLine(text: '第二句歌词'),
        ReferenceLyricLine(text: '第三句歌词'),
      ],
      timed: false,
      format: 'txt',
    );
    final alignment = alignmentService.align(
      document: document,
      referenceLines: input.lines,
    );
    ReferenceAlignmentReviewDecision? decision;

    await pumpReview(
      tester,
      document: document,
      alignment: alignment,
      input: input,
      manuallyEditedLineIndices: const {},
      onResult: (value) => decision = value,
    );

    expect(find.text('需确认'), findsWidgets);
    final checkboxes = tester
        .widgetList<Checkbox>(find.byType(Checkbox))
        .toList();
    expect(checkboxes, hasLength(1));
    expect(checkboxes.single.value, isFalse);
    expect(find.text('没有可应用的修改'), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '补全 1 行'));
    await tester.pumpAndSettle();

    expect(decision, isNotNull);
    expect(decision!.acceptedMissingReferenceIndices, {1});
  });

  testWidgets('歧义匹配行显示替换或插入漏行两种选择', (tester) async {
    const document = LyricDocument(
      language: 'zh',
      lines: [
        LyricLine(
          text: '第一句歌词a',
          startTime: Duration.zero,
          endTime: Duration(seconds: 4),
        ),
        LyricLine(
          text: '第一句歌词b',
          startTime: Duration(seconds: 4),
          endTime: Duration(seconds: 8),
        ),
      ],
    );
    const input = ReferenceLyricInput(
      lines: [ReferenceLyricLine(text: '第一句歌词')],
      timed: false,
      format: 'txt',
    );
    final alignment = alignmentService.align(
      document: document,
      referenceLines: input.lines,
    );

    // 断言域层已标记歧义匹配。
    final entry = alignment.entries.single;
    expect(entry.status, ReferenceLineAlignmentStatus.ambiguous);
    expect(entry.ambiguous, isTrue);

    await pumpReview(
      tester,
      document: document,
      alignment: alignment,
      input: input,
      manuallyEditedLineIndices: const {},
      onResult: (_) {},
    );

    expect(find.text('歧义匹配'), findsOneWidget);
    expect(find.text('替换此行'), findsOneWidget);
    expect(find.text('作为漏行插入'), findsOneWidget);
    expect(find.text('跳过'), findsOneWidget);

    // 三个互斥选择，默认均未选中。
    final checkboxes = find.byType(Checkbox);
    expect(checkboxes, findsNWidgets(3));
    // 通过 element 列表检查默认值均为 false。
    for (final element in tester.widgetList<Checkbox>(checkboxes)) {
      expect(element.value, isFalse);
    }
    expect(find.text('没有可应用的修改'), findsOneWidget);
  });

  testWidgets('歧义匹配选择替换后，参考行进入 acceptedReferenceIndices', (tester) async {
    const document = LyricDocument(
      language: 'zh',
      lines: [
        LyricLine(
          text: '第一句歌词a',
          startTime: Duration.zero,
          endTime: Duration(seconds: 4),
        ),
        LyricLine(
          text: '第一句歌词b',
          startTime: Duration(seconds: 4),
          endTime: Duration(seconds: 8),
        ),
      ],
    );
    const input = ReferenceLyricInput(
      lines: [ReferenceLyricLine(text: '第一句歌词')],
      timed: false,
      format: 'txt',
    );
    final alignment = alignmentService.align(
      document: document,
      referenceLines: input.lines,
    );

    ReferenceAlignmentReviewDecision? decision;
    await pumpReview(
      tester,
      document: document,
      alignment: alignment,
      input: input,
      manuallyEditedLineIndices: const {},
      onResult: (value) => decision = value,
    );

    final checkboxes = find.byType(Checkbox);
    expect(checkboxes, findsNWidgets(3));
    // 第一个选项为“替换此行”。
    await tester.tap(checkboxes.at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '应用 1 行修正'));
    await tester.pumpAndSettle();

    expect(decision, isNotNull);
    expect(decision!.acceptedReferenceIndices, {0});
    expect(decision!.acceptedMissingReferenceIndices, isEmpty);
  });

  testWidgets('歧义匹配选择作为漏行插入后，参考行进入 acceptedMissingReferenceIndices', (
    tester,
  ) async {
    const document = LyricDocument(
      language: 'zh',
      lines: [
        LyricLine(
          text: '第一句歌词a',
          startTime: Duration.zero,
          endTime: Duration(seconds: 4),
        ),
        LyricLine(
          text: '第一句歌词b',
          startTime: Duration(seconds: 4),
          endTime: Duration(seconds: 8),
        ),
      ],
    );
    const input = ReferenceLyricInput(
      lines: [ReferenceLyricLine(text: '第一句歌词')],
      timed: false,
      format: 'txt',
    );
    final alignment = alignmentService.align(
      document: document,
      referenceLines: input.lines,
    );

    ReferenceAlignmentReviewDecision? decision;
    await pumpReview(
      tester,
      document: document,
      alignment: alignment,
      input: input,
      manuallyEditedLineIndices: const {},
      onResult: (value) => decision = value,
    );

    final checkboxes = find.byType(Checkbox);
    expect(checkboxes, findsNWidgets(3));
    // 第二个选项为“作为漏行插入”。
    await tester.tap(checkboxes.at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '补全 1 行'));
    await tester.pumpAndSettle();

    expect(decision, isNotNull);
    expect(decision!.acceptedMissingReferenceIndices, {0});
    expect(decision!.acceptedReferenceIndices, isEmpty);
  });
}

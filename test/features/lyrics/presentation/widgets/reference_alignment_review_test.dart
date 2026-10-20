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
          text: '今天天气真好',
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
        ReferenceLyricLine(text: '明天天气不错'),
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
}

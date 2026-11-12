import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/project_proofread_evidence.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/project_asr_snapshot_dialog.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

LyricLine row(String text, int start, int end, {
  int confidence = 90,
  LyricConfidenceSource source = LyricConfidenceSource.model,
}) => LyricLine(
  text: text,
  startTime: Duration(milliseconds: start),
  endTime: Duration(milliseconds: end),
  confidence: confidence,
  confidenceSource: source,
);

ProjectProofreadEvidenceResult audit({
  List<LyricLine>? primary,
  List<LyricLine>? secondary,
}) => ProjectProofreadEvidenceResult.auditOnly(
  primary: LyricDocument(language: 'en', lines: primary ?? [row('first original', 0, 1000)]),
  primaryEngine: 'qwen3-asr-1.7b',
  secondary: LyricDocument(language: 'zh', lines: secondary ?? [row('second original', 0, 1000)]),
  secondaryEngine: 'whisper.cpp-large-v3',
  capturedAtUtc: DateTime.utc(2026, 11, 7),
);

Future<void> showSnapshot(WidgetTester tester, ProjectProofreadEvidenceResult evidence) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(builder: (context) => Scaffold(
      body: TextButton(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => ProjectAsrSnapshotDialog(evidence: evidence),
        ),
        child: const Text('open audit'),
      ),
    )),
  ));
  await tester.tap(find.text('open audit'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows original comparison and clear read-only disclaimer', (tester) async {
    await showSnapshot(tester, audit());
    expect(find.text('原始双引擎快照（只读）'), findsOneWidget);
    expect(find.textContaining('不代表当前歌词与第二引擎独立一致'), findsOneWidget);
    expect(find.textContaining('音频校验仅为时点检查'), findsOneWidget);
    expect(find.textContaining('2026-11-07T00:00:00.000Z'), findsOneWidget);
    expect(find.textContaining('行号属于各自原稿'), findsOneWidget);
    expect(find.text('原文不同'), findsOneWidget);
    expect(find.text('主稿第 1 行：first original'), findsOneWidget);
    expect(find.text('第二稿第 1 行：second original'), findsOneWidget);
    expect(find.text('关闭'), findsOneWidget);
    expect(find.textContaining('采纳'), findsNothing);
    expect(find.textContaining('应用'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('each original tab exposes its own engine, language and times', (tester) async {
    await showSnapshot(tester, audit());
    await tester.tap(find.text('主引擎原稿'));
    await tester.pumpAndSettle();
    expect(find.text('引擎：qwen3-asr-1.7b · 语言：en'), findsOneWidget);
    expect(find.text('first original'), findsOneWidget);
    expect(find.text('第 1 行 · 00:00.000 – 00:01.000 · 置信度 90'), findsOneWidget);
    await tester.tap(find.text('第二引擎原稿'));
    await tester.pumpAndSettle();
    expect(find.text('引擎：whisper.cpp-large-v3 · 语言：zh'), findsOneWidget);
    expect(find.text('second original'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unscored confidence is unknown, not a placeholder score', (tester) async {
    await showSnapshot(tester, audit(primary: [
      row('unscored', 1000, 2200, confidence: 50, source: LyricConfidenceSource.unscored),
    ]));
    await tester.tap(find.text('主引擎原稿'));
    await tester.pumpAndSettle();
    expect(find.text('第 1 行 · 00:01.000 – 00:02.200 · 置信度未知'), findsOneWidget);
    expect(find.textContaining('置信度 50'), findsNothing);
  });

  testWidgets('one-to-many overlap is shown as ambiguity, not agreement', (tester) async {
    await showSnapshot(tester, audit(
      primary: [row('same', 0, 2000)],
      secondary: [row('same', 0, 1000), row('same', 1000, 2000)],
    ));
    expect(find.text('原文相同（不保证准确）'), findsNothing);
    expect(find.text('原文不同'), findsNothing);
    expect(find.text('重叠关系有歧义，请查看原稿'), findsWidgets);
  });

  testWidgets('exact original agreement is not described as ground truth', (tester) async {
    await showSnapshot(tester, audit(
      primary: [row('same', 0, 1000)],
      secondary: [row('same', 100, 900)],
    ));
    expect(find.text('原文相同（不保证准确）'), findsOneWidget);
    expect(find.text('主稿第 1 行：same'), findsOneWidget);
    expect(find.text('第二稿第 1 行：same'), findsOneWidget);
  });

  testWidgets('unmatched raw segments are displayed separately', (tester) async {
    await showSnapshot(tester, audit(
      primary: [row('first', 0, 1000)],
      secondary: [row('second', 1000, 2000)],
    ));
    expect(find.text('仅主引擎有此时间段'), findsOneWidget);
    expect(find.text('仅第二引擎有此时间段'), findsOneWidget);
    expect(find.text('原文相同（不保证准确）'), findsNothing);
  });

  testWidgets('over-budget comparison retains individually scrollable originals', (tester) async {
    final large = List.generate(401, (i) => row('original $i', i * 1000, i * 1000 + 500));
    await showSnapshot(tester, audit(primary: large));
    expect(find.text('快照超出安全比较限制；请分别查看两份原稿。'), findsOneWidget);
    await tester.tap(find.text('主引擎原稿'));
    await tester.pumpAndSettle();
    expect(find.text('original 0'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('original 0'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('close dismisses without a selection or editable controls', (tester) async {
    await showSnapshot(tester, audit());
    expect(find.byType(Checkbox), findsNothing);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('原始双引擎快照（只读）'), findsNothing);
    expect(find.text('open audit'), findsOneWidget);
  });

  for (final size in [const Size(390, 844), const Size(844, 390), const Size(768, 1024), const Size(1366, 768)]) {
    testWidgets('dialog fits viewport $size', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await showSnapshot(tester, audit());
      expect(find.text('原始双引擎快照（只读）'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

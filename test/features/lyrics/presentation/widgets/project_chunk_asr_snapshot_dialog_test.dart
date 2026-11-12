import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/project_proofread_evidence.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/project_chunk_asr_snapshot_dialog.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

LyricDocument doc(String text, int start, int end) => LyricDocument(
  language: 'en',
  lines: [
    LyricLine(
      text: text,
      startTime: Duration(milliseconds: start),
      endTime: Duration(milliseconds: end),
    ),
  ],
);

List<ProjectProofreadChunk> sampleChunks() => [
  ProjectProofreadChunk(
    index: 0,
    start: Duration.zero,
    end: const Duration(seconds: 3),
    primary: doc('first primary', 500, 1500),
    primaryEngine: 'qwen3-asr-1.7b',
    secondary: doc('first secondary', 750, 1750),
    secondaryEngine: 'whisper.cpp-large-v3',
    capturedAtUtc: DateTime.utc(2026, 11, 7),
  ),
  ProjectProofreadChunk(
    index: 1,
    start: const Duration(seconds: 2),
    end: const Duration(seconds: 4),
    primary: doc('second primary', 2500, 3500),
    primaryEngine: 'qwen3-asr-1.7b',
    secondary: doc('second secondary', 2750, 3750),
    secondaryEngine: 'whisper.cpp-large-v3',
    capturedAtUtc: DateTime.utc(2026, 11, 7),
  ),
];

Future<void> openDialog(
  WidgetTester tester,
  List<ProjectProofreadChunk> chunks,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => ProjectChunkAsrSnapshotDialog(chunks: chunks),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists explicit source time windows and warns about overlap', (
    tester,
  ) async {
    await openDialog(tester, sampleChunks());
    expect(find.text('分片原始双引擎快照（只读）'), findsOneWidget);
    expect(find.textContaining('重叠区可能重复'), findsOneWidget);
    expect(find.textContaining('不比较当前歌词'), findsOneWidget);
    expect(find.textContaining('音源校验仅为时点检查'), findsOneWidget);
    expect(find.text('共 2 个分片，时间为完整音源的绝对时间。'), findsOneWidget);
    expect(find.text('分片 1'), findsOneWidget);
    expect(find.text('分片 2'), findsOneWidget);
    expect(find.text('00:00.000 – 00:03.000'), findsOneWidget);
    expect(find.text('00:02.000 – 00:04.000'), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('采纳'), findsOneWidget); // disclaimer only
    expect(tester.takeException(), isNull);
  });

  testWidgets('selects a single chunk and compares only its two originals', (
    tester,
  ) async {
    await openDialog(tester, sampleChunks());
    await tester.tap(find.text('分片 2'));
    await tester.pumpAndSettle();
    expect(find.text('分片 2 原始快照（只读）'), findsOneWidget);
    expect(find.textContaining('仅比较本分片两份原稿'), findsOneWidget);
    expect(find.text('原文不同'), findsOneWidget);
    expect(find.text('主稿第 1 行：second primary'), findsOneWidget);
    expect(find.text('第二稿第 1 行：second secondary'), findsOneWidget);
    expect(find.text('主稿第 1 行：first primary'), findsNothing);
    expect(find.text('智能校对提案复核'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('transcript tabs show absolute times and original engines', (
    tester,
  ) async {
    await openDialog(tester, sampleChunks());
    await tester.tap(find.text('分片 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('主引擎原稿'));
    await tester.pumpAndSettle();
    expect(find.text('引擎：qwen3-asr-1.7b · 语言：en'), findsOneWidget);
    expect(find.text('second primary'), findsOneWidget);
    expect(
      find.text('第 1 行 · 00:02.500 – 00:03.500 · 置信度 100'),
      findsOneWidget,
    );
    await tester.tap(find.text('第二引擎原稿'));
    await tester.pumpAndSettle();
    expect(find.text('引擎：whisper.cpp-large-v3 · 语言：en'), findsOneWidget);
    expect(find.text('second secondary'), findsOneWidget);
    expect(
      find.text('第 1 行 · 00:02.750 – 00:03.750 · 置信度 100'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'closing an individual chunk returns to the list and permits another',
    (tester) async {
      await openDialog(tester, sampleChunks());
      await tester.tap(find.text('分片 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('关闭').last);
      await tester.pumpAndSettle();
      expect(find.text('分片原始双引擎快照（只读）'), findsOneWidget);
      await tester.tap(find.text('分片 1'));
      await tester.pumpAndSettle();
      expect(find.text('分片 1 原始快照（只读）'), findsOneWidget);
      expect(find.text('主稿第 1 行：first primary'), findsOneWidget);
      expect(find.text('第二稿第 1 行：first secondary'), findsOneWidget);
      await tester.tap(find.text('关闭').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(find.text('分片原始双引擎快照（只读）'), findsNothing);
      expect(find.text('open'), findsOneWidget);
    },
  );

  testWidgets(
    'repeated overlap remains independently available in each chunk',
    (tester) async {
      final chunks = sampleChunks();
      chunks[0] = ProjectProofreadChunk(
        index: 0,
        start: Duration.zero,
        end: const Duration(seconds: 3),
        primary: doc('repeat', 2000, 2900),
        primaryEngine: 'qwen3-asr-1.7b',
        secondary: doc('repeat', 2000, 2900),
        secondaryEngine: 'whisper.cpp-large-v3',
        capturedAtUtc: DateTime.utc(2026),
      );
      chunks[1] = ProjectProofreadChunk(
        index: 1,
        start: const Duration(seconds: 2),
        end: const Duration(seconds: 4),
        primary: doc('repeat', 2000, 2900),
        primaryEngine: 'qwen3-asr-1.7b',
        secondary: doc('repeat', 2000, 2900),
        secondaryEngine: 'whisper.cpp-large-v3',
        capturedAtUtc: DateTime.utc(2026),
      );
      await openDialog(tester, chunks);
      expect(find.text('分片 1'), findsOneWidget);
      expect(find.text('分片 2'), findsOneWidget);
      await tester.tap(find.text('分片 1'));
      await tester.pumpAndSettle();
      expect(find.text('原文相同（不保证准确）'), findsOneWidget);
      await tester.tap(find.text('关闭').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('分片 2'));
      await tester.pumpAndSettle();
      expect(find.text('原文相同（不保证准确）'), findsOneWidget);
      expect(find.text('分片 2 原始快照（只读）'), findsOneWidget);
    },
  );

  testWidgets('large lists are lazy and allow navigation to later chunks', (
    tester,
  ) async {
    final base = sampleChunks().first;
    final chunks = List.generate(
      1000,
      (i) => ProjectProofreadChunk(
        index: i,
        start: Duration(seconds: i * 2),
        end: Duration(seconds: i * 2 + 3),
        primary: base.primary,
        primaryEngine: base.primaryEngine,
        secondary: base.secondary,
        secondaryEngine: base.secondaryEngine,
        capturedAtUtc: base.capturedAtUtc,
      ),
    );
    await openDialog(tester, chunks);
    expect(find.text('共 1000 个分片，时间为完整音源的绝对时间。'), findsOneWidget);
    expect(find.text('分片 1000'), findsNothing);
    await tester.drag(
      find.byKey(const ValueKey('chunk_snapshot_list')),
      const Offset(0, -1000),
    );
    await tester.pumpAndSettle();
    expect(find.text('分片 1'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(390, 844),
    const Size(844, 390),
    const Size(768, 1024),
    const Size(1366, 768),
  ]) {
    testWidgets('chunk list fits simulated viewport $size', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await openDialog(tester, sampleChunks());
      expect(find.text('分片原始双引擎快照（只读）'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

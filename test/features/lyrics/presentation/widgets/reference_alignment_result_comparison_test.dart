import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/reference_alignment_result_comparison.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

void main() {
  testWidgets('shows per-line corrections and insertions and auditions a selected result', (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const before = LyricDocument(
      language: 'en',
      lines: [
        LyricLine(
          id: 'line-a',
          text: 'I got a beer',
          startTime: Duration(seconds: 1),
          endTime: Duration(seconds: 3),
        ),
      ],
    );
    const after = LyricDocument(
      language: 'en',
      lines: [
        LyricLine(
          id: 'line-a',
          text: 'I got myself a beer',
          startTime: Duration(seconds: 1),
          endTime: Duration(seconds: 3),
        ),
        LyricLine(
          id: 'line-b',
          text: 'Oh',
          startTime: Duration(seconds: 3),
          endTime: Duration(seconds: 4),
        ),
      ],
    );

    var previewedIndex = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showReferenceAlignmentResultComparison(
                context,
                before: before,
                after: after,
                onPreviewLine: (index) => previewedIndex = index,
              ),
              child: const Text('打开对比'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开对比'));
    await tester.pumpAndSettle();

    expect(find.text('本次逐行对比'), findsOneWidget);
    expect(find.text('第 1 行 · 文字修正'), findsOneWidget);
    expect(find.text('第 2 行 · 补全新增'), findsOneWidget);
    expect(find.text('试听这一行'), findsNWidgets(2));

    await tester.tap(find.widgetWithText(OutlinedButton, '试听这一行').last);
    await tester.pumpAndSettle();
    expect(previewedIndex, 1);
  });
}

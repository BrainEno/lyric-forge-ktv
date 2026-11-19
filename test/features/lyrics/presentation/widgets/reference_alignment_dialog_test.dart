import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/data/services/local_lyric_file_import_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/reference_lyric_text_parser.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/reference_alignment_dialog.dart';

void main() {
  final parser = ReferenceLyricTextParser(LocalLyricFileImportService());

  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showReferenceAlignmentDialog(
                  context,
                  parser: parser,
                  initialTitle: '测试歌曲',
                ),
                child: const Text('打开参考歌词'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开参考歌词'));
    await tester.pumpAndSettle();
    expect(find.text('参考歌词：纠正文字和时间轴'), findsOneWidget);
  }

  TextField fieldWithLabel(WidgetTester tester, String label) {
    return tester
        .widgetList<TextField>(find.byType(TextField))
        .firstWhere((field) => field.decoration?.labelText == label);
  }

  testWidgets('opens at compact width without intrinsic layout errors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await openDialog(tester);
    expect(tester.takeException(), isNull);

    final titleCenter = tester.getCenter(
      find.byWidget(fieldWithLabel(tester, '参考歌名')),
    );
    final artistCenter = tester.getCenter(
      find.byWidget(fieldWithLabel(tester, '参考艺术家')),
    );
    expect(artistCenter.dy, greaterThan(titleCenter.dy));

    // Hovering used to hit an unlaid-out render box after the layout failure,
    // which left MouseTracker stuck and froze every later mouse event.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(10, 10));
    await tester.pump();
    await mouse.moveTo(titleCenter);
    await tester.pump();
    await mouse.moveTo(artistCenter);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('lays the metadata fields side by side on a wide viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await openDialog(tester);
    expect(tester.takeException(), isNull);

    final titleCenter = tester.getCenter(
      find.byWidget(fieldWithLabel(tester, '参考歌名')),
    );
    final artistCenter = tester.getCenter(
      find.byWidget(fieldWithLabel(tester, '参考艺术家')),
    );
    expect(artistCenter.dy, titleCenter.dy);
    expect(artistCenter.dx, greaterThan(titleCenter.dx));
  });

  group('ReferenceLyricPurpose', () {
    Future<void> openFor(
      WidgetTester tester,
      ReferenceLyricPurpose purpose,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => showReferenceAlignmentDialog(
                    context,
                    parser: parser,
                    initialTitle: '测试歌曲',
                    purpose: purpose,
                  ),
                  child: const Text('打开参考歌词'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开参考歌词'));
      await tester.pumpAndSettle();
    }

    for (final purpose in ReferenceLyricPurpose.values) {
      testWidgets('${purpose.name} titles the dialog after its own flow', (
        tester,
      ) async {
        await openFor(tester, purpose);

        expect(find.text(purpose.title), findsOneWidget);
        expect(find.text(purpose.dialogDetail), findsOneWidget);
        for (final other in ReferenceLyricPurpose.values) {
          if (other == purpose) continue;
          expect(find.text(other.title), findsNothing);
        }
      });
    }

    test('the text-only flow never promises new timing', () {
      final textOnly = ReferenceLyricPurpose.textOnly;
      expect(textOnly.dialogDetail, contains('时间戳保持不变'));
      expect(textOnly.dialogDetail, isNot(contains('推断时间')));
      expect(textOnly.menuDetail, contains('时间戳保持不变'));
      expect(ReferenceLyricPurpose.alignment.dialogDetail, contains('推断时间'));
    });

    test('the two reference flows read as a pair', () {
      const prefix = '参考歌词：';
      expect(ReferenceLyricPurpose.alignment.title, startsWith(prefix));
      expect(ReferenceLyricPurpose.textOnly.title, startsWith(prefix));
      // Neither title carries a version number or engine jargon.
      for (final purpose in ReferenceLyricPurpose.values) {
        expect(purpose.title, isNot(matches(RegExp(r'V\d'))));
        expect(purpose.title, isNot(contains('ASR')));
      }
      // Only the flows with a menu entry carry a menu subtitle.
      expect(ReferenceLyricPurpose.proposal.menuDetail, isNull);
    });

    test('the default stays the alignment flow', () {
      final dialog = ReferenceAlignmentDialog(
        parser: parser,
        initialTitle: '测试歌曲',
      );
      expect(dialog.purpose, ReferenceLyricPurpose.alignment);
    });
  });
}

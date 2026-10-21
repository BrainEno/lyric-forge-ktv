import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/data/services/local_lyric_file_import_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/data/services/reference_lyric_text_parser.dart';
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
    expect(find.text('参考歌词纠正'), findsOneWidget);
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
}

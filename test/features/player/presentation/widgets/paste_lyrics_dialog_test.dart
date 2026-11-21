import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/data/services/local_lyric_file_import_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/online/song_lyrics_lookup.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_file_import_service.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/lyrics_source_sheet.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/paste_lyrics_dialog.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_timing.dart';

const _lrc = '[00:01.00]第一句\n[00:03.50]第二句\n[00:06.00]第三句';

void main() {
  final importer = LocalLyricFileImportService();

  group('parsePastedLyrics', () {
    test('plain text becomes reference lyrics', () {
      final result = parsePastedLyrics(importer, '第一句\n\n  第二句  \n')!;
      expect(result.document.isUntimed, isTrue);
      expect(result.document.lines.map((line) => line.text), ['第一句', '第二句']);
      expect(result.document.metadata['source'], pastedLyricsSource);
      expect(result.format, LyricImportFormat.plainText);
    });

    test('pasted LRC keeps its timing', () {
      final result = parsePastedLyrics(importer, _lrc)!;
      expect(result.document.isTimed, isTrue);
      expect(
        result.document.lines[1].startTime,
        const Duration(milliseconds: 3500),
      );
      expect(result.document.metadata['source'], pastedLyricsSource);
    });

    test('pasted LRC can drop its timing', () {
      final result = parsePastedLyrics(importer, _lrc, stripTimestamps: true)!;
      expect(result.document.isUntimed, isTrue);
      expect(result.document.lines.map((line) => line.text), [
        '第一句',
        '第二句',
        '第三句',
      ]);
    });

    test('blank text gives nothing', () {
      expect(parsePastedLyrics(importer, '  \n '), isNull);
    });
  });

  Future<Future<LyricImportResult?>> open(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox.expand())),
    );
    final future = showPasteLyricsDialog(
      tester.element(find.byType(Scaffold)),
      importer: importer,
      songTitle: '夜航',
    );
    await tester.pumpAndSettle();
    return future;
  }

  testWidgets('saving pasted plain text returns reference lyrics', (
    tester,
  ) async {
    final future = await open(tester);
    expect(find.text('粘贴歌词 · 夜航'), findsOneWidget);
    expect(find.text('还没有可保存的歌词'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('paste-lyrics-text')),
      '第一句\n第二句',
    );
    await tester.pump();
    expect(find.text('共 2 行，纯文本（无时间轴）'), findsOneWidget);
    expect(find.byKey(const ValueKey('paste-lyrics-strip')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('paste-lyrics-save')));
    await tester.pumpAndSettle();
    final result = await future;
    expect(result!.document.isUntimed, isTrue);
  });

  testWidgets('timed text can be saved without its timestamps', (tester) async {
    final future = await open(tester);
    await tester.enterText(
      find.byKey(const ValueKey('paste-lyrics-text')),
      _lrc,
    );
    await tester.pump();
    expect(find.text('共 3 行，带时间轴'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('paste-lyrics-strip')));
    await tester.pump();
    expect(find.text('共 3 行，纯文本（无时间轴）'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('paste-lyrics-save')));
    await tester.pumpAndSettle();
    expect((await future)!.document.isUntimed, isTrue);
  });

  testWidgets('the source sheet offers the three ways', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox.expand())),
    );
    final future = showLyricsSourceSheet(
      tester.element(find.byType(Scaffold)),
      onlineAvailable: true,
      songTitle: '夜航',
    );
    await tester.pumpAndSettle();
    expect(find.text('为“夜航”添加歌词'), findsOneWidget);
    expect(find.text('联网获取歌词（推荐）'), findsOneWidget);
    expect(find.text('导入歌词文件'), findsOneWidget);
    expect(find.text('粘贴歌词文本'), findsOneWidget);
    await tester.tap(find.text('粘贴歌词文本'));
    await tester.pumpAndSettle();
    expect(await future, LyricsSourceChoice.paste);
  });

  testWidgets('without lyric sites the search is not offered', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox.expand())),
    );
    showLyricsSourceSheet(
      tester.element(find.byType(Scaffold)),
      onlineAvailable: false,
    );
    await tester.pumpAndSettle();
    expect(find.text('联网获取歌词（推荐）'), findsNothing);
    expect(find.text('添加歌词'), findsOneWidget);
  });
}

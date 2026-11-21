import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/vocal_check_record.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_batch_text_edit.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_vocal_gap_dialog.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_vocal_restore_dialog.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

// Every lyric below is synthetic text written for these tests.

Duration _ms(int value) => Duration(milliseconds: value);

LyricLine _line(String text, int startMs, int endMs, {String? id}) =>
    LyricLine(text: text, startTime: _ms(startMs), endTime: _ms(endMs), id: id);

LyricVocalCheckRemovedLine _removed(String text, int startMs, int endMs) =>
    LyricVocalCheckRemovedLine(
      text: text,
      start: _ms(startMs),
      end: _ms(endMs),
    );

final _record = LyricVocalCheckRecord(
  removedLines: [
    _removed('whispered intro', 1000, 4000),
    _removed('quiet bridge', 50000, 53000),
    _removed('   ', 70000, 71000),
    _removed('soft outro', 90000, 93000),
  ],
  retimedLines: 2,
);

LyricDocument _draft({LyricVocalCheckRecord? record, List<LyricLine>? lines}) =>
    LyricDocument(
      language: 'en',
      lines:
          lines ??
          [
            _line('verse one', 10000, 14000, id: 'a'),
            _line('verse two', 60000, 64000, id: 'b'),
          ],
      metadata: {
        if (record != null) LyricVocalCheckRecord.metadataKey: record.toJson(),
      },
    );

final _previews = <({int index, Duration start, Duration end})>[];

Future<LyricBatchTextEdit? Function()> _open(
  WidgetTester tester, {
  required LyricDocument document,
  bool preview = false,
}) async {
  LyricBatchTextEdit? result;
  _previews.clear();
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async => result = await showLyricVocalRestoreDialog(
                context,
                document: document,
                onPreviewSpan: preview
                    ? (index, start, end) =>
                          _previews.add((index: index, start: start, end: end))
                    : null,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return () => result;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

FilledButton _confirm(WidgetTester tester) => tester.widget<FilledButton>(
  find.byKey(const ValueKey('vocal_restore_confirm')),
);

bool? _checked(WidgetTester tester, int index) => tester
    .widget<Checkbox>(find.byKey(ValueKey('vocal_restore_check_$index')))
    .value;

List<String> _texts(LyricDocument document) => [
  for (final line in document.lines) line.text,
];

void main() {
  testWidgets('lists every removed row, all checked', (tester) async {
    await _open(tester, document: _draft(record: _record));
    expect(find.text(LyricVocalCheckStrings.restoreTitle), findsOneWidget);
    expect(find.text('人声检查删除了 4 行'), findsOneWidget);
    for (var index = 0; index < 4; index++) {
      expect(find.byKey(ValueKey('vocal_restore_row_$index')), findsOneWidget);
      expect(_checked(tester, index), isTrue);
    }
    expect(find.text('whispered intro'), findsOneWidget);
    expect(find.text('0:50.0–0:53.0'), findsOneWidget);
    expect(find.text('（空行）'), findsOneWidget);
    expect(find.text('恢复 4 行'), findsOneWidget);
    expect(find.text('全不选'), findsOneWidget);
  });

  testWidgets('restores all rows as hand-confirmed rows', (tester) async {
    final result = await _open(tester, document: _draft(record: _record));
    await _tap(tester, find.byKey(const ValueKey('vocal_restore_confirm')));

    final edit = result()!;
    expect(_texts(edit.document), [
      'whispered intro',
      'verse one',
      'quiet bridge',
      'verse two',
      '   ',
      'soft outro',
    ]);
    expect(edit.label, LyricVocalCheckStrings.restoreTitle);
    expect(edit.selectedLineIndex, 0);
    expect(edit.message, contains('已恢复 4 行'));
    expect(edit.message, contains('未写入磁盘'));
    expect(edit.manuallyEditedLineIds, hasLength(4));
    expect(edit.manuallyEditedLineIds, isNot(contains('a')));
    expect(edit.manuallyEditedLineIds, isNot(contains('b')));
    final record = LyricVocalCheckRecord.fromMetadata(edit.document.metadata)!;
    expect(record.removedLines, isEmpty);
    expect(record.restoredLines, 4);
    expect(record.retimedLines, 2);
  });

  testWidgets('restores only the checked rows', (tester) async {
    final result = await _open(tester, document: _draft(record: _record));
    await _tap(tester, find.byKey(const ValueKey('vocal_restore_check_0')));
    await _tap(tester, find.byKey(const ValueKey('vocal_restore_check_2')));
    expect(_checked(tester, 0), isFalse);
    expect(find.text('恢复 2 行'), findsOneWidget);
    expect(find.text('全选'), findsOneWidget);

    await _tap(tester, find.byKey(const ValueKey('vocal_restore_confirm')));
    final edit = result()!;
    expect(_texts(edit.document), [
      'verse one',
      'quiet bridge',
      'verse two',
      'soft outro',
    ]);
    expect(edit.selectedLineIndex, 1);
    expect(edit.manuallyEditedLineIds, {
      edit.document.lines[1].id,
      edit.document.lines[3].id,
    });
    final record = LyricVocalCheckRecord.fromMetadata(edit.document.metadata)!;
    expect(
      [for (final line in record.removedLines) line.text],
      ['whispered intro', '   '],
    );
    expect(record.restoredLines, 2);
  });

  testWidgets('select none disables restoring; select all brings it back', (
    tester,
  ) async {
    await _open(tester, document: _draft(record: _record));
    await _tap(tester, find.byKey(const ValueKey('vocal_restore_toggle_all')));
    for (var index = 0; index < 4; index++) {
      expect(_checked(tester, index), isFalse);
    }
    expect(_confirm(tester).onPressed, isNull);
    expect(find.text('请勾选要恢复的行'), findsOneWidget);

    await _tap(tester, find.byKey(const ValueKey('vocal_restore_toggle_all')));
    for (var index = 0; index < 4; index++) {
      expect(_checked(tester, index), isTrue);
    }
    expect(_confirm(tester).onPressed, isNotNull);
  });

  testWidgets('warns about rows that overlap an existing row', (tester) async {
    final result = await _open(
      tester,
      document: _draft(
        record: _record,
        lines: [
          _line('verse one', 10000, 14000),
          _line('typed by hand', 50500, 52000),
        ],
      ),
    );
    await _tap(tester, find.byKey(const ValueKey('vocal_restore_confirm')));
    expect(result()!.message, contains('其中 1 行和已有的行时间重叠'));
  });

  testWidgets('previews a removed row at its old time', (tester) async {
    await _open(tester, document: _draft(record: _record), preview: true);
    await _tap(tester, find.byKey(const ValueKey('vocal_restore_preview_1')));
    expect(_previews.single, (index: 1, start: _ms(50000), end: _ms(53000)));

    await _tap(tester, find.byKey(const ValueKey('vocal_restore_preview_3')));
    // After the last row the preview borrows the last row's index.
    expect(_previews.last, (index: 1, start: _ms(90000), end: _ms(93000)));

    await _tap(tester, find.byKey(const ValueKey('vocal_restore_preview_0')));
    expect(_previews.last.index, 0);
  });

  testWidgets('no preview callback, no preview buttons', (tester) async {
    await _open(tester, document: _draft(record: _record));
    expect(find.byKey(const ValueKey('vocal_restore_preview_0')), findsNothing);
  });

  testWidgets('a record without removed rows says so', (tester) async {
    await _open(
      tester,
      document: _draft(record: const LyricVocalCheckRecord(retimedLines: 1)),
    );
    expect(find.text(LyricVocalCheckStrings.noRemoved), findsOneWidget);
    expect(_confirm(tester).onPressed, isNull);
  });

  testWidgets('cancelling changes nothing', (tester) async {
    final result = await _open(tester, document: _draft(record: _record));
    await _tap(tester, find.text('取消'));
    expect(result(), isNull);
  });

  group('restore all without a dialog', () {
    test('puts every removed row back', () {
      final edit = lyricRestoreAllRemovedLinesEdit(_draft(record: _record))!;
      expect(edit.document.lines, hasLength(6));
      expect(edit.manuallyEditedLineIds, hasLength(4));
      expect(edit.selectedLineIndex, 0);
      expect(edit.message, contains('已恢复 4 行'));
    });

    test('is null without removed rows', () {
      expect(lyricRestoreAllRemovedLinesEdit(_draft()), isNull);
      expect(
        lyricRestoreAllRemovedLinesEdit(
          _draft(record: const LyricVocalCheckRecord(retimedLines: 3)),
        ),
        isNull,
      );
    });

    test('a second restore has nothing left', () {
      final edit = lyricRestoreAllRemovedLinesEdit(_draft(record: _record))!;
      expect(lyricRestoreAllRemovedLinesEdit(edit.document), isNull);
    });
  });
}

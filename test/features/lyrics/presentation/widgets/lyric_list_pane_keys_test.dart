import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_editor_toolbar.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_list_pane.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

import 'lyric_list_pane_test.dart' show reviewFor;

/// What the list asked its host to do.
class _Calls {
  final selected = <int>[];
  final deleted = <int>[];
  final updated = <(int, LyricLine)>[];

  /// Keys that the list left for the widgets above it.
  final passedOn = <LogicalKeyboardKey>[];
}

LyricDocument _document(int count, {Map<String, dynamic> metadata = const {}}) {
  return LyricDocument(
    language: 'zh',
    metadata: metadata,
    lines: [
      for (var index = 0; index < count; index++)
        LyricLine(
          id: 'line-$index',
          text: '第 ${index + 1} 行',
          startTime: Duration(seconds: index * 4),
          endTime: Duration(seconds: index * 4 + 3),
        ),
    ],
  );
}

void main() {
  late _Calls calls;

  setUp(() => calls = _Calls());

  Widget host({
    int count = 3,
    int? selectedLine = 1,
    List<int>? visible,
    Map<String, dynamic> metadata = const {},
    Map<String, dynamic>? candidate,
  }) {
    final document = _document(count, metadata: metadata);
    return MaterialApp(
      home: Scaffold(
        body: Focus(
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent) calls.passedOn.add(event.logicalKey);
            return KeyEventResult.ignored;
          },
          child: SizedBox(
            height: 600,
            child: LyricListPane(
              document: document,
              visibleIndices: visible ?? List<int>.generate(count, (i) => i),
              review: reviewFor(
                document,
                filter: LyricReviewFilter.all,
                selectedLine: selectedLine,
              ),
              activeAuditionLineIndex: null,
              auditionPlaying: false,
              currentPlaybackLine: null,
              focusRequestId: 0,
              focusLineIndex: null,
              fallbackCandidateFor: (_) => candidate,
              onPreviewLine: null,
              onInsertedLineFocus: (_) {},
              onSelectLine: calls.selected.add,
              onUpdateLine: (index, line) => calls.updated.add((index, line)),
              onDeleteLine: calls.deleted.add,
            ),
          ),
        ),
      ),
    );
  }

  /// Taps row [index] so the list has keyboard focus, then forgets the tap.
  Future<void> focusList(WidgetTester tester, {int index = 1}) async {
    await tester.tap(find.text('第 ${index + 1} 行'));
    // The row also listens for a double tap.
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    calls.selected.clear();
  }

  Future<void> withControl(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  group('keys', () {
    testWidgets('arrows move the selection through the shown rows', (
      tester,
    ) async {
      await tester.pumpWidget(host());
      await focusList(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);

      expect(calls.selected, [2, 0]);
      expect(calls.passedOn, isEmpty);
    });

    testWidgets('arrows skip rows the filter hides', (tester) async {
      await tester.pumpWidget(host(count: 5, visible: [0, 1, 4]));
      await focusList(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);

      expect(calls.selected, [4]);
    });

    testWidgets('Tab and Space are left to the app', (tester) async {
      await tester.pumpWidget(host());
      await focusList(tester);
      final before = FocusManager.instance.primaryFocus;

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      expect(calls.passedOn, contains(LogicalKeyboardKey.tab));
      expect(FocusManager.instance.primaryFocus, isNot(same(before)));

      await focusList(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(calls.passedOn, contains(LogicalKeyboardKey.space));
    });

    testWidgets('Delete alone keeps the line; Ctrl + Delete removes it', (
      tester,
    ) async {
      await tester.pumpWidget(host());
      await focusList(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      expect(calls.deleted, isEmpty);
      expect(calls.passedOn, contains(LogicalKeyboardKey.delete));

      await withControl(tester, LogicalKeyboardKey.delete);
      expect(calls.deleted, [1]);
    });

    testWidgets('Ctrl + Backspace removes the line too', (tester) async {
      await tester.pumpWidget(host());
      await focusList(tester);

      await withControl(tester, LogicalKeyboardKey.backspace);

      expect(calls.deleted, [1]);
    });

    testWidgets('Enter opens the inline editor and selects the row', (
      tester,
    ) async {
      await tester.pumpWidget(host());
      await focusList(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(find.byType(InlineLyricEditorRow), findsOneWidget);
      expect(calls.selected, [1]);
    });

    testWidgets('F2 opens the inline editor', (tester) async {
      await tester.pumpWidget(host());
      await focusList(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pump();

      expect(find.byType(InlineLyricEditorRow), findsOneWidget);
    });

    testWidgets('Ctrl + F focuses the search field', (tester) async {
      await tester.pumpWidget(host(count: 10));
      await focusList(tester);

      await withControl(tester, LogicalKeyboardKey.keyF);

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.focusNode?.hasFocus, isTrue);
    });

    testWidgets('Ctrl + F is left to the app when there is no search', (
      tester,
    ) async {
      await tester.pumpWidget(host());
      await focusList(tester);

      await withControl(tester, LogicalKeyboardKey.keyF);

      expect(find.byType(TextField), findsNothing);
      expect(calls.passedOn, contains(LogicalKeyboardKey.keyF));
    });

    testWidgets('without a selection the arrows are left to the app', (
      tester,
    ) async {
      await tester.pumpWidget(host(selectedLine: null));
      await focusList(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);

      expect(calls.selected, isEmpty);
      expect(calls.passedOn, contains(LogicalKeyboardKey.arrowDown));
    });

    testWidgets('keys go to the editor while a row is being edited', (
      tester,
    ) async {
      await tester.pumpWidget(host());
      await focusList(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      calls.selected.clear();

      await withControl(tester, LogicalKeyboardKey.delete);

      expect(calls.deleted, isEmpty);
    });
  });

  group('row actions', () {
    testWidgets('copy from the right-click menu copies the text', (
      tester,
    ) async {
      final copied = <String?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String?);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(host());

      await tester.tap(find.text('第 2 行'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('复制文字'));
      await tester.pumpAndSettle();

      expect(copied, ['第 2 行']);
      expect(find.text('已复制：第 2 行'), findsOneWidget);
    });

    testWidgets('the last row offers no merge', (tester) async {
      await tester.pumpWidget(host());

      await tester.tap(find.text('第 3 行'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      expect(find.text('复制文字'), findsOneWidget);
      expect(find.text('与下一行合并'), findsNothing);
    });

    testWidgets('tapping a time edits that line', (tester) async {
      await tester.pumpWidget(host());

      await tester.tap(find.text('00:04.00'));
      // The row around the time also listens for a double tap.
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
      expect(find.text('编辑开始时间'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '00:05');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(calls.updated, hasLength(1));
      final (index, line) = calls.updated.single;
      expect(index, 1);
      expect(line.startTime, const Duration(seconds: 5));
      expect(line.endTime, const Duration(seconds: 7));
    });

    testWidgets('an impossible time is refused with a reason', (tester) async {
      await tester.pumpWidget(host());

      await tester.tap(find.text('00:07.00'));
      // The row around the time also listens for a double tap.
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '00:03');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(calls.updated, isEmpty);
      expect(find.text('结束时间不能早于开始时间'), findsOneWidget);
    });
  });

  group('candidates', () {
    testWidgets('only highlighted rows show their candidate', (tester) async {
      await tester.pumpWidget(
        host(
          candidate: const {'alternativeText': 'x'},
          metadata: {
            'fallbackHighlightLimit': 1,
            'fallbackCandidates': [
              {'lineIndex': 2},
              {'lineIndex': 0},
            ],
          },
        ),
      );

      expect(find.text('双引擎'), findsOneWidget);
      expect(
        find.textContaining('已保存候选 2 行 · 未复核 2 行 · 重点标记 1 行（当前筛选 1 行）'),
        findsOneWidget,
      );
    });

    testWidgets('without saved candidates every row shows its own', (
      tester,
    ) async {
      await tester.pumpWidget(host(candidate: const {'alternativeText': 'x'}));

      expect(find.text('双引擎'), findsNWidgets(3));
      expect(find.textContaining('已保存候选'), findsNothing);
    });
  });
}

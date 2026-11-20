import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/theme/color_tokens.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_review_priority_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_editor_atoms.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_review_row.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_row_semantics.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

const _line = LyricLine(
  text: '月亮代表我的心',
  startTime: Duration(seconds: 10),
  endTime: Duration(seconds: 14),
);

const _longLine = LyricLine(
  text: '这是一句非常非常长的歌词，用来确认选中时可以换行显示更多文字内容，不会被截断',
  startTime: Duration(seconds: 20),
  endTime: Duration(seconds: 26),
);

void main() {
  final calls = <String>[];

  setUp(calls.clear);

  LyricReviewRow row({
    LyricLine line = _line,
    bool selected = false,
    bool playing = false,
    bool reviewed = false,
    bool edited = false,
    bool secondary = false,
    Map<String, dynamic>? candidate,
    LyricReviewPriority? priority,
    bool allActions = true,
    bool withCopy = true,
  }) {
    VoidCallback? record(String name) =>
        allActions ? () => calls.add(name) : null;
    return LyricReviewRow(
      index: 4,
      line: line,
      fallbackCandidate: candidate,
      isReviewed: reviewed,
      isSecondarySuggestion: secondary,
      priority: priority,
      selected: selected,
      playing: playing,
      hasAudio: false,
      auditionIsPlaying: false,
      onPreview: null,
      onTap: () => calls.add('tap'),
      onDoubleTap: record('editText'),
      onEditStartTime: record('editStart'),
      onEditEndTime: record('editEnd'),
      onSetStartFromPlayback: record('startFromPlayback'),
      onSetEndFromPlayback: record('endFromPlayback'),
      onSplit: record('split'),
      onMergeWithNext: record('merge'),
      onCopy: withCopy ? record('copy') : null,
      onDelete: record('delete'),
      isManuallyEdited: edited,
    );
  }

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(1200, 800),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Center(child: child)),
      ),
    );
  }

  group('menu actions', () {
    test('the menu follows the screen-reader order', () {
      expect(row().menuActions, LyricRowMenuAction.values);
      expect(
        [for (final action in LyricRowMenuAction.values) action.label],
        [
          LyricRowSemantics.editText,
          LyricRowSemantics.editStart,
          LyricRowSemantics.editEnd,
          LyricRowSemantics.startFromPlayback,
          LyricRowSemantics.endFromPlayback,
          LyricRowSemantics.split,
          LyricRowSemantics.merge,
          LyricRowSemantics.copy,
          LyricRowSemantics.delete,
        ],
      );
    });

    test('only offered edits are listed', () {
      expect(row(allActions: false).menuActions, isEmpty);
      expect(
        row(withCopy: false).menuActions,
        isNot(contains(LyricRowMenuAction.copy)),
      );
    });

    test('each action runs its own callback', () {
      final subject = row();
      for (final action in LyricRowMenuAction.values) {
        subject.callbackFor(action)!.call();
      }
      expect(calls, [for (final action in LyricRowMenuAction.values) action.name]);
    });

    test('editing the text names its shortcut; delete is destructive', () {
      expect(LyricRowMenuAction.editText.menuLabel, '编辑文字（双击）');
      expect(LyricRowMenuAction.copy.menuLabel, '复制文字');
      expect(LyricRowMenuAction.delete.destructive, isTrue);
      expect(
        LyricRowMenuAction.values.where((action) => action.destructive),
        [LyricRowMenuAction.delete],
      );
    });
  });

  group('text', () {
    test('an empty line says so', () {
      final empty = row(
        line: const LyricLine(
          text: '  ',
          startTime: Duration.zero,
          endTime: Duration(seconds: 1),
        ),
      );
      expect(empty.displayText, '（空歌词）');
      expect(row().displayText, _line.text);
    });

    test('long is more than 28 characters', () {
      expect(row().isLongText, isFalse);
      expect(row(line: _longLine).isLongText, isTrue);
    });

    testWidgets('a selected long line wraps to four lines', (tester) async {
      await pump(tester, row(line: _longLine, selected: true));
      final text = tester.widget<Text>(find.text(_longLine.text));
      expect(text.maxLines, 4);

      await pump(tester, row(line: _longLine));
      expect(tester.widget<Text>(find.text(_longLine.text)).maxLines, 2);
    });

    testWidgets('a phone shows one line', (tester) async {
      await pump(tester, row(line: _longLine), size: const Size(390, 844));
      expect(tester.widget<Text>(find.text(_longLine.text)).maxLines, 1);
    });

    testWidgets('a hand-edited line is italic, also when expanded', (
      tester,
    ) async {
      await pump(tester, row(line: _longLine, selected: true, edited: true));
      final text = tester.widget<Text>(find.text(_longLine.text));
      expect(text.style?.fontStyle, FontStyle.italic);
    });

    testWidgets('the playing line is bold and shows the playing icon', (
      tester,
    ) async {
      await pump(tester, row(playing: true));
      expect(
        tester.widget<Text>(find.text(_line.text)).style?.fontWeight,
        FontWeight.w700,
      );
      expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);
      expect(find.text('5'), findsNothing);
    });

    testWidgets('the row number shows when not playing', (tester) async {
      await pump(tester, row(edited: true));
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('both times are shown and underlined when editable', (
      tester,
    ) async {
      await pump(tester, row());
      final start = tester.widget<Text>(find.text('00:10.00'));
      expect(start.style?.decoration, TextDecoration.underline);
      expect(find.text('00:14.00'), findsOneWidget);

      await pump(tester, row(allActions: false));
      expect(
        tester.widget<Text>(find.text('00:10.00')).style?.decoration,
        isNull,
      );
    });

    testWidgets('tapping a time edits it', (tester) async {
      await pump(tester, row());
      await tester.tap(find.text('00:14.00'));
      // The row also listens for a double tap, so the arena waits for it.
      await tester.pump(const Duration(milliseconds: 500));
      expect(calls, ['editEnd']);
    });
  });

  group('badges', () {
    final priority = LyricReviewPriority(
      lineIndex: 4,
      score: 50,
      reasons: const [
        LyricReviewPriorityReason(LyricReviewPriorityReasonCode.emptyLyrics),
      ],
    );

    testWidgets('candidate, suggestion and priority on a wide layout', (
      tester,
    ) async {
      await pump(
        tester,
        row(
          candidate: const {'alternativeText': 'x'},
          secondary: true,
          priority: priority,
        ),
      );
      expect(find.text('双引擎'), findsOneWidget);
      expect(find.text('建议补入'), findsOneWidget);
      expect(find.text('优先 50'), findsOneWidget);
      expect(find.byTooltip('歌词为空'), findsOneWidget);
      final badge = tester.widget<LyricTinyBadge>(
        find.widgetWithText(LyricTinyBadge, '优先 50'),
      );
      expect(badge.warning, isTrue);
    });

    testWidgets('a low priority is not a warning', (tester) async {
      await pump(
        tester,
        row(
          priority: const LyricReviewPriority(
            lineIndex: 4,
            score: 30,
            reasons: [],
          ),
        ),
      );
      final badge = tester.widget<LyricTinyBadge>(
        find.widgetWithText(LyricTinyBadge, '优先 30'),
      );
      expect(badge.warning, isFalse);
    });

    testWidgets('short labels on a phone', (tester) async {
      await pump(
        tester,
        row(
          candidate: const {'alternativeText': 'x'},
          secondary: true,
          priority: priority,
        ),
        size: const Size(390, 844),
      );
      expect(find.text('双擎'), findsOneWidget);
      expect(find.text('补入'), findsOneWidget);
      expect(find.text('复核'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    });

    testWidgets('a reviewed row only says so', (tester) async {
      await pump(
        tester,
        row(
          reviewed: true,
          candidate: const {'alternativeText': 'x'},
          secondary: true,
          priority: priority,
        ),
      );
      expect(find.text('已复核'), findsOneWidget);
      expect(find.text('双引擎'), findsNothing);
      expect(find.text('建议补入'), findsNothing);
      expect(find.text('优先 50'), findsNothing);
    });

    testWidgets('a chorus line is marked on a wide layout', (tester) async {
      await pump(
        tester,
        row(
          line: const LyricLine(
            text: '副歌这一句',
            startTime: Duration.zero,
            endTime: Duration(seconds: 2),
            isChorus: true,
          ),
        ),
      );
      expect(find.text('副歌'), findsOneWidget);
    });

    testWidgets('the selected row hints at editing', (tester) async {
      await pump(tester, row(selected: true));
      expect(find.byTooltip('双击或按 F2 编辑'), findsOneWidget);
    });
  });

  group('right-click menu', () {
    Future<void> openMenu(WidgetTester tester, Widget subject) async {
      await pump(tester, subject);
      await tester.tap(find.text(_line.text), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
    }

    testWidgets('lists every edit, including copy', (tester) async {
      await openMenu(tester, row());

      for (final action in LyricRowMenuAction.values) {
        expect(find.text(action.menuLabel), findsOneWidget, reason: action.name);
      }
    });

    testWidgets('copy from the menu copies', (tester) async {
      await openMenu(tester, row());

      await tester.tap(find.text('复制文字'));
      await tester.pumpAndSettle();

      expect(calls, ['copy']);
    });

    testWidgets('delete is in the error colour', (tester) async {
      await openMenu(tester, row());

      final label = tester.widget<Text>(find.text('删除此行'));
      expect(label.style?.color, AppColors.errorText);
      final icon = tester.widget<Icon>(find.byIcon(Icons.delete_outline_rounded));
      expect(icon.color, AppColors.errorText);
    });

    testWidgets('dismissing runs nothing', (tester) async {
      await openMenu(tester, row());

      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(calls, isEmpty);
      expect(find.text('复制文字'), findsNothing);
    });

    testWidgets('a read-only row opens no menu', (tester) async {
      await openMenu(tester, row(allActions: false, withCopy: false));

      expect(find.byType(PopupMenuItem<LyricRowMenuAction>), findsNothing);
    });
  });
}

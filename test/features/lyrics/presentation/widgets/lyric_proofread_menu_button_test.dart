import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/auto_proofread_dialogs.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_batch_text_edit.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_editor_actions.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_find_replace_dialog.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_proofread_menu_button.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('one button replaces the separate proofreading entry points', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        LyricProofreadMenuButton(
          onSmartProofread: () {},
          onReferenceAlignment: () {},
          onViewComparison: () {},
          onUndoAlignment: () {},
          onRestoreBackup: () {},
        ),
      ),
    );

    expect(find.text(LyricProofreadMenuButton.label), findsOneWidget);
    // None of the individual flows is visible before the menu is opened.
    expect(find.text('智能校对'), findsNothing);
    expect(find.text('粘贴参考歌词校对'), findsNothing);
    expect(find.text('撤销最近更改'), findsNothing);
    expect(find.text('恢复对齐前版本'), findsNothing);
  });

  testWidgets('the menu explains the reference and no-reference strategies', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        LyricProofreadMenuButton(
          onSmartProofread: () {},
          onReferenceAlignment: () {},
        ),
      ),
    );

    await tester.tap(find.text(LyricProofreadMenuButton.label));
    await tester.pumpAndSettle();

    expect(find.text('智能校对'), findsOneWidget);
    expect(
      find.text(LyricProofreadMenuButton.smartProofreadDetail),
      findsOneWidget,
    );
    expect(find.text('粘贴参考歌词校对'), findsOneWidget);
    expect(find.text('一键校对找不到歌词时用；粘贴或导入歌词，逐行对比后应用'), findsOneWidget);
    // The removed text-only flow (D-053) has no entry.
    expect(find.textContaining('只改文字'), findsNothing);
    // Availability-driven entries stay hidden when the editor has nothing to
    // show yet.
    expect(find.text('查看逐行对比'), findsNothing);
    expect(find.text('恢复对齐前版本'), findsNothing);
  });

  testWidgets('menu entries run the flow they promise', (tester) async {
    final fired = <String>[];

    await tester.pumpWidget(
      _host(
        LyricProofreadMenuButton(
          onSmartProofread: () => fired.add('smart'),
          onReferenceAlignment: () => fired.add('alignment'),
          onViewComparison: () => fired.add('comparison'),
          onUndoAlignment: () => fired.add('undo'),
          onRestoreBackup: () => fired.add('restore'),
        ),
      ),
    );

    for (final entry in {
      '智能校对': 'smart',
      '粘贴参考歌词校对': 'alignment',
      '查看逐行对比': 'comparison',
      '撤销最近更改': 'undo',
      '恢复对齐前版本': 'restore',
    }.entries) {
      await tester.tap(find.text(LyricProofreadMenuButton.label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(entry.key));
      await tester.pumpAndSettle();
      expect(fired.last, entry.value);
    }

    expect(fired, hasLength(5));
  });

  testWidgets('entries are listed under labelled sections in a fixed order', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        LyricProofreadMenuButton(
          onRestoreBackup: () {},
          onTapSync: () {},
          onFindReplace: () {},
          onTextCleanup: () {},
          onSmartProofread: () {},
        ),
      ),
    );

    await tester.tap(find.text(LyricProofreadMenuButton.label));
    await tester.pumpAndSettle();

    final expectedOrder = [
      LyricProofreadGroup.correction.label,
      LyricProofreadMenuButton.smartProofreadTitle,
      LyricProofreadGroup.text.label,
      LyricFindReplaceStrings.actionTitle,
      LyricProofreadGroup.timing.label,
      '打轴（边听边标时间）',
      LyricProofreadGroup.checks.label,
      LyricProofreadGroup.review.label,
      '恢复对齐前版本',
    ];
    final tops = [
      for (final text in expectedOrder) tester.getTopLeft(find.text(text)).dy,
    ];
    for (var index = 1; index < tops.length; index++) {
      expect(
        tops[index],
        greaterThan(tops[index - 1]),
        reason: '${expectedOrder[index]} after ${expectedOrder[index - 1]}',
      );
    }
    // Section titles are labels, not extra actions; the checks are one
    // collapsed submenu until it is opened.
    expect(find.byType(MenuItemButton), findsNWidgets(4));
    expect(find.byType(SubmenuButton), findsOneWidget);
    expect(find.text('清理识别文本'), findsNothing);
    expect(find.byType(Divider), findsNWidgets(4));

    await tester.tap(find.text(LyricProofreadGroup.checks.label));
    await tester.pumpAndSettle();
    expect(find.text('清理识别文本'), findsOneWidget);
  });

  testWidgets('一键校对已包含的单项检查收进一个子菜单', (tester) async {
    final fired = <String>[];
    await tester.pumpWidget(
      _host(
        LyricProofreadMenuButton(
          onTextCleanup: () => fired.add('cleanup'),
          onTimelineRepair: () => fired.add('repair'),
          onPaceCheck: () => fired.add('pace'),
        ),
      ),
    );

    await tester.tap(find.text(LyricProofreadMenuButton.label));
    await tester.pumpAndSettle();
    expect(find.text(LyricProofreadGroup.checks.detail!), findsOneWidget);
    expect(find.text(LyricProofreadGroup.checks.label), findsOneWidget);

    await tester.tap(find.text(LyricProofreadGroup.checks.label));
    await tester.pumpAndSettle();
    await tester.tap(find.text('检查时间轴'));
    await tester.pumpAndSettle();
    expect(fired, ['repair']);
  });

  testWidgets('sections without an available entry are hidden', (tester) async {
    await tester.pumpWidget(
      _host(LyricProofreadMenuButton(onSmartProofread: () {})),
    );

    await tester.tap(find.text(LyricProofreadMenuButton.label));
    await tester.pumpAndSettle();

    expect(find.text(LyricProofreadGroup.correction.label), findsOneWidget);
    expect(find.text(LyricProofreadGroup.text.label), findsNothing);
    expect(find.text(LyricProofreadGroup.timing.label), findsNothing);
    expect(find.text(LyricProofreadGroup.review.label), findsNothing);
    expect(find.byType(Divider), findsNothing);
  });

  testWidgets('renders nothing when every flow is unavailable', (tester) async {
    await tester.pumpWidget(_host(const LyricProofreadMenuButton()));

    expect(find.text(LyricProofreadMenuButton.label), findsNothing);
    expect(find.byType(IconButton), findsNothing);
  });

  testWidgets('the compact variant is an icon button with the same menu', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        LyricProofreadMenuButton(
          compact: true,
          onSmartProofread: () {},
          onReferenceAlignment: () {},
        ),
      ),
    );

    expect(find.text(LyricProofreadMenuButton.label), findsNothing);
    expect(find.byTooltip(LyricProofreadMenuButton.label), findsOneWidget);

    await tester.tap(find.byTooltip(LyricProofreadMenuButton.label));
    await tester.pumpAndSettle();

    expect(find.text('智能校对'), findsOneWidget);
    expect(find.text('粘贴参考歌词校对'), findsOneWidget);
  });

  group('forActions', () {
    test('maps every batch tool to its own entry', () {
      final opened = <LyricBatchTextTool>[];
      final button = LyricProofreadMenuButton.forActions(
        LyricProofreadActions(onBatchTextTool: opened.add),
      );

      final entries = <VoidCallback?>[
        button.onRepetitionConsistency,
        button.onTextCleanup,
        button.onAsrLoopCheck,
        button.onMissedRepeatCheck,
        button.onSpanRecognition,
        button.onVocalGapRecognition,
        button.onRestoreRemovedLines,
        button.onLineStructure,
        button.onTimelineRepair,
        button.onTimingShift,
        button.onPaceCheck,
        button.onTapSync,
        button.onWordTap,
        button.onWordTimingCheck,
        button.onFindReplace,
      ];
      for (final entry in entries) {
        entry!();
      }

      expect(opened, [
        LyricBatchTextTool.repetitionConsistency,
        LyricBatchTextTool.textCleanup,
        LyricBatchTextTool.asrLoopCheck,
        LyricBatchTextTool.missedRepeatCheck,
        LyricBatchTextTool.spanRecognition,
        LyricBatchTextTool.vocalGapRecognition,
        LyricBatchTextTool.restoreRemovedLines,
        LyricBatchTextTool.lineStructure,
        LyricBatchTextTool.timelineRepair,
        LyricBatchTextTool.timingShift,
        LyricBatchTextTool.paceCheck,
        LyricBatchTextTool.tapSync,
        LyricBatchTextTool.wordTap,
        LyricBatchTextTool.wordTimingCheck,
        LyricBatchTextTool.findReplace,
      ]);
      // Word timing editing belongs to the inspector, not the menu.
      expect(opened, isNot(contains(LyricBatchTextTool.wordTimingEdit)));
    });

    test('passes the document-level callbacks through unchanged', () {
      void alignment() {}
      void smart() {}
      void compare() {}
      void undo() {}
      void restore() {}
      final button = LyricProofreadMenuButton.forActions(
        LyricProofreadActions(
          onReferenceAlignment: alignment,
          onSmartProofread: smart,
          onViewAlignmentComparison: compare,
          onUndoReferenceAlignment: undo,
          onRestoreAlignment: restore,
        ),
        compact: true,
      );

      expect(button.compact, isTrue);
      expect(button.onReferenceAlignment, same(alignment));
      expect(button.onSmartProofread, same(smart));
      expect(button.onViewComparison, same(compare));
      expect(button.onUndoAlignment, same(undo));
      expect(button.onRestoreBackup, same(restore));
      // Without a batch tool callback none of the batch entries exist.
      expect(button.onTapSync, isNull);
      expect(button.onFindReplace, isNull);
    });

    testWidgets('an empty group renders nothing', (tester) async {
      await tester.pumpWidget(
        _host(LyricProofreadMenuButton.forActions(LyricProofreadActions.none)),
      );

      expect(find.text(LyricProofreadMenuButton.label), findsNothing);
      expect(find.byType(IconButton), findsNothing);
    });
  });

  testWidgets('一键校对排在最前，点击即运行', (tester) async {
    final fired = <String>[];
    await tester.pumpWidget(
      _host(
        LyricProofreadMenuButton(
          onAutoProofread: () => fired.add('auto'),
          onSmartProofread: () => fired.add('smart'),
          onReferenceAlignment: () {},
        ),
      ),
    );

    await tester.tap(find.text(LyricProofreadMenuButton.label));
    await tester.pumpAndSettle();

    final auto = tester.getTopLeft(find.text(AutoProofreadStrings.actionTitle));
    final smart = tester.getTopLeft(find.text('智能校对'));
    expect(auto.dy, lessThan(smart.dy));
    expect(find.text(AutoProofreadStrings.actionDetail), findsOneWidget);

    await tester.tap(find.text(AutoProofreadStrings.actionTitle));
    await tester.pumpAndSettle();
    expect(fired, ['auto']);
  });
}

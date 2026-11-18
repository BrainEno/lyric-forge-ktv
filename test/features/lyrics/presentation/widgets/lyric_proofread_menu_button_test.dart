import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_proofread_menu_button.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('one button replaces the six proofreading entry points', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        LyricProofreadMenuButton(
          onProofreadV2: () {},
          onReferenceAlignment: () {},
          onReferenceProofread: () {},
          onViewComparison: () {},
          onUndoAlignment: () {},
          onRestoreBackup: () {},
        ),
      ),
    );

    expect(find.text(LyricProofreadMenuButton.label), findsOneWidget);
    // None of the individual flows is visible before the menu is opened.
    expect(find.text('智能校对'), findsNothing);
    expect(find.text('参考歌词纠正'), findsNothing);
    expect(find.text('逐行智能纠错（保留时间戳）'), findsNothing);
    expect(find.text('撤销最近更改'), findsNothing);
    expect(find.text('恢复对齐前版本'), findsNothing);
  });

  testWidgets('the menu explains the reference and no-reference strategies', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        LyricProofreadMenuButton(
          onProofreadV2: () {},
          onReferenceAlignment: () {},
          onReferenceProofread: () {},
        ),
      ),
    );

    await tester.tap(find.text(LyricProofreadMenuButton.label));
    await tester.pumpAndSettle();

    expect(find.text('智能校对'), findsOneWidget);
    expect(find.text('不需要参考歌词；生成不写盘的提案，逐行对比后再应用'), findsOneWidget);
    expect(find.text('参考歌词纠正'), findsOneWidget);
    expect(find.text('逐行智能纠错（保留时间戳）'), findsOneWidget);
    expect(find.text('有参考歌词；只改文字，时间戳保持不变'), findsOneWidget);
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
          onProofreadV2: () => fired.add('v2'),
          onReferenceAlignment: () => fired.add('alignment'),
          onReferenceProofread: () => fired.add('proofread'),
          onViewComparison: () => fired.add('comparison'),
          onUndoAlignment: () => fired.add('undo'),
          onRestoreBackup: () => fired.add('restore'),
        ),
      ),
    );

    for (final entry in {
      '智能校对': 'v2',
      '参考歌词纠正': 'alignment',
      '逐行智能纠错（保留时间戳）': 'proofread',
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

    expect(fired, hasLength(6));
  });

  testWidgets('entries are listed under labelled sections in a fixed order', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        LyricProofreadMenuButton(
          onRestoreBackup: () {},
          onTapSync: () {},
          onTextCleanup: () {},
          onProofreadV2: () {},
        ),
      ),
    );

    await tester.tap(find.text(LyricProofreadMenuButton.label));
    await tester.pumpAndSettle();

    final expectedOrder = [
      LyricProofreadGroup.correction.label,
      LyricProofreadMenuButton.smartProofreadTitle,
      LyricProofreadGroup.text.label,
      '清理识别文本',
      LyricProofreadGroup.timing.label,
      '打轴（边听边标时间）',
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
    // Section titles are labels, not extra actions.
    expect(find.byType(MenuItemButton), findsNWidgets(4));
    expect(find.byType(Divider), findsNWidgets(3));
  });

  testWidgets('sections without an available entry are hidden', (tester) async {
    await tester.pumpWidget(
      _host(LyricProofreadMenuButton(onProofreadV2: () {})),
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
          onProofreadV2: () {},
          onReferenceAlignment: () {},
        ),
      ),
    );

    expect(find.text(LyricProofreadMenuButton.label), findsNothing);
    expect(find.byTooltip(LyricProofreadMenuButton.label), findsOneWidget);

    await tester.tap(find.byTooltip(LyricProofreadMenuButton.label));
    await tester.pumpAndSettle();

    expect(find.text('智能校对'), findsOneWidget);
    expect(find.text('参考歌词纠正'), findsOneWidget);
  });
}

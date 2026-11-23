import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/widgets/undo_snack_bar.dart';

void main() {
  Future<ScaffoldMessengerState> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox.expand())),
    );
    return tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger));
  }

  testWidgets('撤销 runs the undo and shows its result', (tester) async {
    final messenger = await pump(tester);
    var undone = 0;
    showUndoSnackBar(
      messenger,
      message: '已删除',
      onUndo: () async {
        undone++;
        return '已恢复';
      },
    );
    await tester.pumpAndSettle();
    expect(find.text('已删除'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(undone, 1);
    expect(find.text('已恢复'), findsOneWidget);
  });

  testWidgets('a failing undo is reported', (tester) async {
    final messenger = await pump(tester);
    showUndoSnackBar(
      messenger,
      message: '已删除',
      onUndo: () async => throw StateError('gone'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(find.textContaining('没能撤销'), findsOneWidget);
  });

  testWidgets('a new offer replaces the one showing', (tester) async {
    final messenger = await pump(tester);
    showUndoSnackBar(messenger, message: '第一次', onUndo: () async => null);
    await tester.pumpAndSettle();
    showUndoSnackBar(messenger, message: '第二次', onUndo: () async => null);
    await tester.pumpAndSettle();
    expect(find.text('第一次'), findsNothing);
    expect(find.text('第二次'), findsOneWidget);
  });

  testWidgets('it stays up long enough to reach', (tester) async {
    final messenger = await pump(tester);
    showUndoSnackBar(messenger, message: '已删除', onUndo: () async => null);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('已删除'), findsOneWidget);
    expect(
      undoSnackBarDuration,
      greaterThanOrEqualTo(const Duration(seconds: 8)),
    );
  });
}

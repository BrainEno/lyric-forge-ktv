import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/project_save_conflict_dialog.dart';

class _DialogHarness {
  late Future<ProjectSaveConflictChoice> choice;
}

void main() {
  Future<_DialogHarness> openDialog(WidgetTester tester) async {
    final harness = _DialogHarness();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                harness.choice = showProjectSaveConflictDialog(
                  context,
                  latestRevision: 4,
                );
              },
              child: const Text('Save'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    return harness;
  }

  testWidgets('explains that edits remain and offers explicit resolutions', (
    tester,
  ) async {
    await openDialog(tester);

    expect(find.text('工程已在其他位置更新'), findsOneWidget);
    expect(find.textContaining('本次保存未应用'), findsOneWidget);
    expect(find.textContaining('你的编辑仍保留'), findsOneWidget);
    expect(find.textContaining('版本为 4'), findsOneWidget);
    expect(find.text('继续编辑'), findsOneWidget);
    expect(find.text('重新载入最新版'), findsOneWidget);
    expect(find.text('用当前歌词覆盖最新版'), findsOneWidget);

    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
  });

  testWidgets('keep editing is the non-destructive default choice', (
    tester,
  ) async {
    final harness = await openDialog(tester);
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();

    expect(await harness.choice, ProjectSaveConflictChoice.keepEditing);
  });

  testWidgets('reload choice is explicit', (tester) async {
    final harness = await openDialog(tester);
    await tester.tap(find.text('重新载入最新版'));
    await tester.pumpAndSettle();

    expect(await harness.choice, ProjectSaveConflictChoice.reloadLatest);
  });

  testWidgets('overwrite choice is explicit', (tester) async {
    final harness = await openDialog(tester);
    await tester.tap(find.text('用当前歌词覆盖最新版'));
    await tester.pumpAndSettle();

    expect(await harness.choice, ProjectSaveConflictChoice.overwriteLatest);
  });
}

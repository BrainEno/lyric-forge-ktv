import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_batch_text_edit.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_edit_shortcuts.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_find_replace_dialog.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_proofread_menu_button.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_repetition_consistency_dialog.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_text_cleanup_dialog.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

// Synthetic lines written for these tests, not taken from a song.
LyricDocument _doc(List<String> texts) => LyricDocument(
  language: 'zh',
  lines: [
    for (final (index, text) in texts.indexed)
      LyricLine(
        id: 'l$index',
        text: text,
        startTime: Duration(seconds: index * 4),
        endTime: Duration(seconds: index * 4 + 3),
      ),
  ],
);

typedef _Opener = Future<LyricBatchTextEdit?> Function(BuildContext context);

void main() {
  late LyricBatchTextEdit? result;

  Future<void> open(WidgetTester tester, _Opener opener) async {
    result = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async => result = await opener(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  VoidCallback? confirmCallback(WidgetTester tester, String key) =>
      tester.widget<FilledButton>(find.byKey(ValueKey(key))).onPressed;

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  group('find and replace', () {
    testWidgets('previews matches and replaces the selected rows', (
      tester,
    ) async {
      final document = _doc(['我碍你 我碍你', '你好', '你碍我', '他碍她']);
      await open(
        tester,
        (context) => showLyricFindReplaceDialog(
          context,
          document: document,
          protectedIndices: const {},
        ),
      );

      expect(find.text(LyricFindReplaceStrings.actionTitle), findsOneWidget);
      expect(confirmCallback(tester, 'find_replace_confirm'), isNull);
      expect(find.text('输入要查找的文字。'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('find_replace_find_field')),
        '碍',
      );
      await tester.enterText(
        find.byKey(const ValueKey('find_replace_replacement_field')),
        '爱',
      );
      await tester.pumpAndSettle();
      expect(find.text('找到 3 行、4 处匹配；将替换 3 行。'), findsOneWidget);
      expect(find.text('我爱你 我爱你'), findsOneWidget);

      // Leave out the last row.
      await tapVisible(
        tester,
        find.descendant(
          of: find.byKey(const ValueKey('find_replace_row_3')),
          matching: find.byType(Checkbox),
        ),
      );
      expect(find.text('找到 3 行、4 处匹配；将替换 2 行。'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('find_replace_confirm')));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.document.lines.map((line) => line.text), [
        '我爱你 我爱你',
        '你好',
        '你爱我',
        '他碍她',
      ]);
      expect(result!.manuallyEditedLineIds, {'l0', 'l2'});
      expect(result!.selectedLineIndex, 0);
      expect(result!.message, LyricFindReplaceStrings.applied(2, 3));
    });

    testWidgets('protected rows are skipped until the user opts in', (
      tester,
    ) async {
      await open(
        tester,
        (context) => showLyricFindReplaceDialog(
          context,
          document: _doc(['我碍你', '你碍我']),
          protectedIndices: const {0},
          initialQuery: '碍',
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('find_replace_replacement_field')),
        '爱',
      );
      await tester.pumpAndSettle();

      expect(find.text('同时替换手动编辑过的行'), findsOneWidget);
      expect(find.textContaining('手动编辑过，已跳过'), findsOneWidget);
      expect(find.text('找到 2 行、2 处匹配；将替换 1 行。'), findsOneWidget);

      await tapVisible(tester, find.text('同时替换手动编辑过的行'));
      expect(find.text('找到 2 行、2 处匹配；将替换 2 行。'), findsOneWidget);
    });
  });

  group('repeated-line consistency', () {
    testWidgets('pre-selects a clear majority and unifies the outlier', (
      tester,
    ) async {
      final document = _doc(['夜空中最亮的星', '能否听清那仰望的人', '夜空中最亮的星', '夜空中最亮的心']);
      await open(
        tester,
        (context) => showLyricRepetitionConsistencyDialog(
          context,
          document: document,
          protectedIndices: const {},
        ),
      );

      expect(find.text(LyricRepetitionStrings.actionTitle), findsOneWidget);
      expect(find.text('发现 1 组写法不一致的重复行；已选 1 组，将修改 1 行。'), findsOneWidget);
      expect(find.text('统一为“夜空中最亮的星”'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('repetition_confirm')));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.document.lines[3].text, '夜空中最亮的星');
      expect(result!.manuallyEditedLineIds, {'l3'});
      expect(result!.message, LyricRepetitionStrings.applied(1, 1));
    });

    testWidgets('an undecided group waits for the user to choose', (
      tester,
    ) async {
      await open(
        tester,
        (context) => showLyricRepetitionConsistencyDialog(
          context,
          document: _doc(['夜空中最亮的星', '夜空中最亮的心']),
          protectedIndices: const {},
        ),
      );

      expect(find.text('先选择一种写法'), findsOneWidget);
      expect(confirmCallback(tester, 'repetition_confirm'), isNull);

      await tapVisible(
        tester,
        find.byKey(const ValueKey('repetition_variant_1')),
      );
      expect(find.text('统一为“夜空中最亮的心”'), findsOneWidget);
      expect(confirmCallback(tester, 'repetition_confirm'), isNotNull);

      await tester.tap(find.byKey(const ValueKey('repetition_confirm')));
      await tester.pumpAndSettle();
      expect(result!.document.lines.first.text, '夜空中最亮的心');
    });

    testWidgets('says so when every repeat is consistent', (tester) async {
      await open(
        tester,
        (context) => showLyricRepetitionConsistencyDialog(
          context,
          document: _doc(['夜空中最亮的星', '夜空中最亮的星']),
          protectedIndices: const {},
        ),
      );
      expect(find.text(LyricRepetitionStrings.nothingFound), findsOneWidget);
      expect(confirmCallback(tester, 'repetition_confirm'), isNull);
    });
  });

  group('text clean-up', () {
    testWidgets('previews rewrites and removals and applies them', (
      tester,
    ) async {
      final document = _doc(['我爱你，你爱我。', '[音乐]', '一起唱']);
      await open(
        tester,
        (context) => showLyricTextCleanupDialog(
          context,
          document: document,
          protectedIndices: const {},
        ),
      );

      expect(find.text(LyricTextCleanupStrings.actionTitle), findsOneWidget);
      expect(find.text('清理 1 行、删除 1 行'), findsOneWidget);

      // Switching the removal rule off keeps the annotation row.
      await tapVisible(
        tester,
        find.byKey(const ValueKey('cleanup_rule_removeAnnotationOnlyLines')),
      );
      expect(find.text('清理 1 行'), findsOneWidget);
      await tapVisible(
        tester,
        find.byKey(const ValueKey('cleanup_rule_removeAnnotationOnlyLines')),
      );

      await tester.tap(find.byKey(const ValueKey('cleanup_confirm')));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.document.lines.map((line) => line.text), [
        '我爱你 你爱我',
        '一起唱',
      ]);
      expect(result!.manuallyEditedLineIds, isEmpty);
      expect(result!.message, LyricTextCleanupStrings.applied(1, 1));
      expect(result!.selectedLineIndex, 0);
    });

    testWidgets('nothing to clean disables the confirm button', (tester) async {
      await open(
        tester,
        (context) => showLyricTextCleanupDialog(
          context,
          document: _doc(['我爱你', '一起唱']),
          protectedIndices: const {},
        ),
      );
      expect(find.text('无需清理'), findsOneWidget);
      expect(confirmCallback(tester, 'cleanup_confirm'), isNull);
    });
  });

  testWidgets('the proofreading menu offers the three tools', (tester) async {
    final fired = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: LyricProofreadMenuButton(
              onProofreadV2: () {},
              onRepetitionConsistency: () => fired.add('repeat'),
              onTextCleanup: () => fired.add('cleanup'),
              onFindReplace: () => fired.add('replace'),
            ),
          ),
        ),
      ),
    );

    for (final entry in {
      LyricRepetitionStrings.actionTitle: 'repeat',
      LyricTextCleanupStrings.actionTitle: 'cleanup',
      LyricFindReplaceStrings.actionTitle: 'replace',
    }.entries) {
      await tester.tap(find.text(LyricProofreadMenuButton.label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(entry.key));
      await tester.pumpAndSettle();
      expect(fired.last, entry.value);
    }
    expect(fired, ['repeat', 'cleanup', 'replace']);
  });

  group('find-and-replace shortcut', () {
    Future<List<String>> pump(WidgetTester tester) async {
      final calls = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: LyricEditShortcuts(
            onUndo: () => calls.add('undo'),
            onRedo: () => calls.add('redo'),
            onFindReplace: () => calls.add('replace'),
            child: const Scaffold(
              body: Focus(autofocus: true, child: SizedBox.expand()),
            ),
          ),
        ),
      );
      await tester.pump();
      return calls;
    }

    Future<void> press(
      WidgetTester tester,
      LogicalKeyboardKey modifier, {
      bool shift = false,
    }) async {
      await tester.sendKeyDownEvent(modifier);
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(modifier);
      await tester.pump();
    }

    testWidgets('Ctrl+H opens find and replace', (tester) async {
      final calls = await pump(tester);
      await press(tester, LogicalKeyboardKey.controlLeft);
      expect(calls, ['replace']);
    });

    testWidgets('on macOS Ctrl+H is left to text fields; Cmd+Shift+H works', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final calls = await pump(tester);
        await press(tester, LogicalKeyboardKey.controlLeft);
        expect(calls, isEmpty);
        await press(tester, LogicalKeyboardKey.metaLeft, shift: true);
        expect(calls, ['replace']);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_tap_sync_dialog.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_word_tap_dialog.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_word_timing_edit_dialog.dart';
import 'package:lyric_forge_ktv/features/search/domain/keyboard_shortcut_catalog.dart';
import 'package:lyric_forge_ktv/features/search/presentation/widgets/keyboard_shortcuts_panel.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(1280, 800),
    double textScale = 1,
    TargetPlatform platform = TargetPlatform.windows,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: platform),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showKeyboardShortcuts(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('lists every group with Ctrl on Windows', (tester) async {
    await pump(tester);
    expect(find.byKey(KeyboardShortcutsPanel.panelKey), findsOneWidget);
    for (final group in keyboardShortcutGroups(apple: false)) {
      await tester.scrollUntilVisible(
        find.text(group.title),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text(group.title), findsOneWidget);
    }
    expect(find.text('Ctrl'), findsWidgets);
    expect(find.text('⌘'), findsNothing);
  });

  testWidgets('says ⌘ on macOS', (tester) async {
    await pump(tester, platform: TargetPlatform.macOS);
    expect(find.text('⌘'), findsWidgets);
    expect(find.text('Ctrl'), findsNothing);
  });

  testWidgets('closes from its button', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(KeyboardShortcutsPanel), findsNothing);
  });

  testWidgets('fits a narrow window without overflow', (tester) async {
    await pump(tester, size: const Size(320, 568), textScale: 2);
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  group('the catalog mirrors the bindings', () {
    final groups = {
      for (final group in keyboardShortcutGroups(apple: false))
        group.title: group,
    };

    Set<String> keysOf(String title) => {
      for (final shortcut in groups[title]!.shortcuts) ...[
        ...shortcut.keys,
        ...?shortcut.alternative,
      ],
    };

    /// The keys a dialog names in its own hint line, e.g. "空格 打点 · …".
    Set<String> hintKeys(String hint) => {
      for (final part in hint.split(' · '))
        for (final key in part.split(' ').first.split('/'))
          if (key.isNotEmpty) key,
    };

    test('逐行打轴 has the tap sync keys', () {
      expect(keysOf('逐行打轴'), containsAll(hintKeys(LyricTapSyncStrings.keys)));
    });

    test('逐字打点 has the word tap keys', () {
      expect(keysOf('逐字打点'), containsAll(hintKeys(LyricWordTapStrings.keys)));
    });

    test('逐字微调 has the word timing keys', () {
      expect(
        keysOf('逐字微调'),
        containsAll(hintKeys(LyricWordTimingEditStrings.keys)),
      );
      // "[ / ]" names only [ before its first space.
      expect(keysOf('逐字微调'), contains(']'));
    });

    test('the macOS list swaps find and replace and drops Ctrl+Y', () {
      final apple = keyboardShortcutGroups(
        apple: true,
      ).singleWhere((group) => group.title == '歌词校对').shortcuts;
      final find = apple.singleWhere((item) => item.action == '查找和替换');
      expect(find.keys, ['⌘', 'Shift', 'H']);
      final redo = apple.singleWhere((item) => item.action == '重做');
      expect(redo.alternative, isNull);
    });
  });
}

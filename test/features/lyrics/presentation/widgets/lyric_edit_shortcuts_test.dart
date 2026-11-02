import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_edit_shortcuts.dart';

void main() {
  late List<String> calls;

  setUp(() => calls = <String>[]);

  Future<void> pumpEditor(WidgetTester tester, {VoidCallback? onSave}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LyricEditShortcuts(
          onUndo: () => calls.add('undo'),
          onRedo: () => calls.add('redo'),
          onSave: onSave,
          // Key events bubble up from the focused node, and CallbackShortcuts
          // only sees events raised inside its subtree, so the harness gives
          // it a focusable child the way the editor's list does.
          child: const Scaffold(
            body: Focus(autofocus: true, child: SizedBox.expand()),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> press(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    LogicalKeyboardKey? modifier,
    bool shift = false,
  }) async {
    if (modifier != null) await tester.sendKeyDownEvent(modifier);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(key);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    if (modifier != null) await tester.sendKeyUpEvent(modifier);
    await tester.pump();
  }

  testWidgets('Ctrl+Z 撤销，Cmd+Z 也撤销', (tester) async {
    await pumpEditor(tester);

    await press(
      tester,
      LogicalKeyboardKey.keyZ,
      modifier: LogicalKeyboardKey.controlLeft,
    );
    expect(calls, ['undo']);

    await press(
      tester,
      LogicalKeyboardKey.keyZ,
      modifier: LogicalKeyboardKey.metaLeft,
    );
    expect(calls, ['undo', 'undo']);
  });

  testWidgets('Ctrl+Shift+Z 与 Ctrl+Y 都重做', (tester) async {
    await pumpEditor(tester);

    await press(
      tester,
      LogicalKeyboardKey.keyZ,
      modifier: LogicalKeyboardKey.controlLeft,
      shift: true,
    );
    expect(calls, ['redo']);

    await press(
      tester,
      LogicalKeyboardKey.keyY,
      modifier: LogicalKeyboardKey.controlLeft,
    );
    expect(calls, ['redo', 'redo']);
  });

  testWidgets('单独的 Z 不触发撤销', (tester) async {
    await pumpEditor(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.pump();

    expect(calls, isEmpty);
  });

  testWidgets('保存快捷键仍然可用', (tester) async {
    await pumpEditor(tester, onSave: () => calls.add('save'));

    await press(
      tester,
      LogicalKeyboardKey.keyS,
      modifier: LogicalKeyboardKey.controlLeft,
    );

    expect(calls, ['save']);
  });

  testWidgets('没有提供保存回调时不绑定 Ctrl+S', (tester) async {
    await pumpEditor(tester);

    await press(
      tester,
      LogicalKeyboardKey.keyS,
      modifier: LogicalKeyboardKey.controlLeft,
    );

    expect(calls, isEmpty);
  });
}

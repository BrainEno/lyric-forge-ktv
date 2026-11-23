import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/search/presentation/widgets/global_search_shortcuts.dart';

void main() {
  late List<String> calls;

  Future<void> pump(WidgetTester tester) {
    return tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => GlobalSearchShortcuts(
          onSearch: () => calls.add('search'),
          onShortcuts: () => calls.add('shortcuts'),
          child: child!,
        ),
        home: const Scaffold(body: TextField()),
      ),
    );
  }

  Future<void> chord(
    WidgetTester tester,
    LogicalKeyboardKey modifier,
    LogicalKeyboardKey key,
  ) async {
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(modifier);
    await tester.pump();
  }

  setUp(() => calls = []);

  testWidgets('Ctrl+K opens the search, even from a text field', (
    tester,
  ) async {
    await pump(tester);
    await chord(
      tester,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.keyK,
    );
    expect(calls, ['search']);

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await chord(
      tester,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.keyK,
    );
    expect(calls, ['search', 'search']);
  });

  testWidgets('on macOS only ⌘K counts', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await pump(tester);
      await chord(tester, LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.keyK);
      expect(calls, ['search']);
      // Ctrl+K deletes to the end of the line in macOS text fields.
      await chord(
        tester,
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.keyK,
      );
      expect(calls, ['search']);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Ctrl+/ and F1 open the shortcut panel', (tester) async {
    await pump(tester);
    await chord(
      tester,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.slash,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await tester.pump();
    expect(calls, ['shortcuts', 'shortcuts']);
  });

  testWidgets('? opens the panel only while nothing is focused', (
    tester,
  ) async {
    // Shift+/ on a US keyboard: the logical key stays slash, the character
    // is ?.
    Future<void> question() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '?');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
    }

    await pump(tester);
    await question();
    expect(calls, ['shortcuts']);

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await question();
    expect(calls, ['shortcuts'], reason: 'typed into the field instead');
  });

  test('other chords are left alone', () {
    final keyboard = HardwareKeyboard.instance;
    const event = KeyUpEvent(
      physicalKey: PhysicalKeyboardKey.keyK,
      logicalKey: LogicalKeyboardKey.keyK,
      timeStamp: Duration.zero,
    );
    expect(
      GlobalSearchShortcuts.commandFor(
        event,
        keyboard: keyboard,
        nothingFocused: true,
      ),
      isNull,
    );
  });
}

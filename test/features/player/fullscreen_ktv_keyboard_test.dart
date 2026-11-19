import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/fullscreen_ktv_interaction_surface.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/global_playback_shortcuts.dart';

/// Keyboard transport of the fullscreen KTV surface: the bare keys a video
/// player takes, handed to `onCommand`, without stealing Space from a button
/// that was reached with Tab.
void main() {
  late List<GlobalPlaybackCommand> commands;
  late List<LogicalKeyboardKey> bubbled;
  late bool accept;

  setUp(() {
    commands = <GlobalPlaybackCommand>[];
    bubbled = <LogicalKeyboardKey>[];
    accept = true;
  });

  Future<void> pumpSurface(
    WidgetTester tester, {
    Duration hideDelay = const Duration(seconds: 30),
    bool withCommands = true,
    VoidCallback? onButton,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Focus(
            // Records what the surface left unhandled.
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent) bubbled.add(event.logicalKey);
              return KeyEventResult.ignored;
            },
            child: FullscreenKtvInteractionSurface(
              controlsHideDelay: hideDelay,
              onExit: () {},
              onCommand: withCommands
                  ? (command) {
                      if (!accept) return false;
                      commands.add(command);
                      return true;
                    }
                  : null,
              builder: (context, controlsVisible) => Column(
                children: [
                  Text(controlsVisible ? 'controls-visible' : 'hidden'),
                  TextButton(
                    onPressed: onButton ?? () {},
                    child: const Text('button'),
                  ),
                  const Expanded(child: Center(child: Text('lyrics'))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> press(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    List<LogicalKeyboardKey> modifiers = const [],
  }) async {
    for (final modifier in modifiers) {
      await tester.sendKeyDownEvent(modifier);
    }
    await tester.sendKeyDownEvent(key);
    await tester.sendKeyUpEvent(key);
    for (final modifier in modifiers.reversed) {
      await tester.sendKeyUpEvent(modifier);
    }
    await tester.pump();
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
  }

  testWidgets('Space toggles playback while the surface has focus', (
    tester,
  ) async {
    await pumpSurface(tester);

    await press(tester, LogicalKeyboardKey.space);

    expect(commands, [GlobalPlaybackCommand.togglePlayPause]);
    expect(bubbled, isNot(contains(LogicalKeyboardKey.space)));
    await dispose(tester);
  });

  testWidgets('bare and Shift arrows seek', (tester) async {
    await pumpSurface(tester);

    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    await press(
      tester,
      LogicalKeyboardKey.arrowRight,
      modifiers: [LogicalKeyboardKey.shiftLeft],
    );

    expect(commands, [
      GlobalPlaybackCommand.seekForward,
      GlobalPlaybackCommand.seekBack,
      GlobalPlaybackCommand.seekForward,
    ]);
    await dispose(tester);
  });

  testWidgets('Ctrl and Meta arrows change the song', (tester) async {
    await pumpSurface(tester);

    await press(
      tester,
      LogicalKeyboardKey.arrowRight,
      modifiers: [LogicalKeyboardKey.controlLeft],
    );
    await press(
      tester,
      LogicalKeyboardKey.arrowLeft,
      modifiers: [LogicalKeyboardKey.metaLeft],
    );

    expect(commands, [
      GlobalPlaybackCommand.next,
      GlobalPlaybackCommand.previous,
    ]);
    await dispose(tester);
  });

  testWidgets('a held arrow keeps seeking, a held Space does not repeat', (
    tester,
  ) async {
    await pumpSurface(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.pump();

    expect(commands, [
      GlobalPlaybackCommand.seekForward,
      GlobalPlaybackCommand.seekForward,
      GlobalPlaybackCommand.seekForward,
      GlobalPlaybackCommand.togglePlayPause,
    ]);
    await dispose(tester);
  });

  testWidgets('Alt, Ctrl+Shift and other keys are left alone', (tester) async {
    await pumpSurface(tester);

    await press(
      tester,
      LogicalKeyboardKey.arrowRight,
      modifiers: [LogicalKeyboardKey.altLeft],
    );
    await press(
      tester,
      LogicalKeyboardKey.arrowLeft,
      modifiers: [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.shiftLeft],
    );
    await press(tester, LogicalKeyboardKey.keyK);

    expect(commands, isEmpty);
    expect(bubbled, contains(LogicalKeyboardKey.keyK));
    await dispose(tester);
  });

  testWidgets('a command with nothing to control is left to the app', (
    tester,
  ) async {
    accept = false;
    await pumpSurface(tester);

    await press(tester, LogicalKeyboardKey.arrowRight);

    expect(commands, isEmpty);
    expect(bubbled, contains(LogicalKeyboardKey.arrowRight));
    await dispose(tester);
  });

  testWidgets('without onCommand the keys only show the controls', (
    tester,
  ) async {
    await pumpSurface(
      tester,
      hideDelay: const Duration(milliseconds: 100),
      withCommands: false,
    );
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('hidden'), findsOneWidget);

    await press(tester, LogicalKeyboardKey.space);

    expect(find.text('controls-visible'), findsOneWidget);
    expect(bubbled, contains(LogicalKeyboardKey.space));
    await dispose(tester);
  });

  testWidgets('a handled command shows hidden controls', (tester) async {
    await pumpSurface(tester, hideDelay: const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('hidden'), findsOneWidget);

    await press(tester, LogicalKeyboardKey.arrowLeft);

    expect(find.text('controls-visible'), findsOneWidget);
    expect(commands, [GlobalPlaybackCommand.seekBack]);
    await dispose(tester);
  });

  testWidgets('Space activates a focused button instead of toggling', (
    tester,
  ) async {
    var buttonPresses = 0;
    await pumpSurface(tester, onButton: () => buttonPresses++);

    // Tab moves focus from the surface to its first button.
    await press(tester, LogicalKeyboardKey.tab);
    await press(tester, LogicalKeyboardKey.space);

    expect(commands, isEmpty);
    expect(buttonPresses, 1);

    // Clicking the lyrics gives the keys back to the surface.
    await tester.tap(find.text('lyrics'));
    await tester.pump(const Duration(milliseconds: 350));
    await press(tester, LogicalKeyboardKey.space);

    expect(commands, [GlobalPlaybackCommand.togglePlayPause]);
    await dispose(tester);
  });

  group('keyHint', () {
    test('uses Ctrl on Windows and Linux', () {
      for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
        final hint = FullscreenKtvInteractionSurface.keyHint(
          platform: platform,
        );
        expect(hint, contains('Ctrl+←/→ 上一首/下一首'));
      }
    });

    test('uses ⌘ on macOS', () {
      final hint = FullscreenKtvInteractionSurface.keyHint(
        platform: TargetPlatform.macOS,
      );
      expect(hint, contains('⌘←/→ 上一首/下一首'));
      expect(hint, isNot(contains('Ctrl')));
    });

    test('names the seek step and Esc', () {
      final hint = FullscreenKtvInteractionSurface.keyHint(
        platform: TargetPlatform.windows,
      );
      final seconds = GlobalPlaybackShortcuts.seekStep.inSeconds;
      expect(hint, startsWith('空格 播放/暂停'));
      expect(hint, contains('←/→ 后退/前进 $seconds 秒'));
      expect(hint, endsWith('Esc 退出'));
    });
  });
}

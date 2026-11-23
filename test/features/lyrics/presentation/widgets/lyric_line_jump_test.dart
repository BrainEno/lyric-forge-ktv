import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_line_jump.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_list_logic.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_list_pane.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

import 'lyric_list_pane_test.dart' show reviewFor;

/// Row i reads "row i+1" and is sung over [4i+1, 4i+3) seconds.
LyricDocument _document(int count) {
  return LyricDocument(
    language: 'zh',
    lines: [
      for (var index = 0; index < count; index++)
        LyricLine(
          id: 'l$index',
          text: 'row ${index + 1}',
          startTime: Duration(seconds: index * 4 + 1),
          endTime: Duration(seconds: index * 4 + 3),
        ),
    ],
  );
}

/// The list as the editor shows it, with a selection that follows taps and
/// arrow keys and a playhead the test moves.
class _Host extends StatefulWidget {
  const _Host({
    required this.document,
    required this.jump,
    this.followPlayback = false,
    this.playing,
  });

  final LyricDocument document;
  final LyricLineJumpController jump;
  final bool followPlayback;
  final int? playing;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  int? selected;
  late int? playing = widget.playing;

  void play(int? index) => setState(() => playing = index);

  @override
  Widget build(BuildContext context) {
    final document = widget.document;
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 600,
          child: LyricListPane(
            document: document,
            visibleIndices: [for (var i = 0; i < document.lines.length; i++) i],
            review: reviewFor(
              document,
              selectedLine: selected,
              followPlayback: widget.followPlayback,
            ),
            activeAuditionLineIndex: null,
            auditionPlaying: false,
            currentPlaybackLine: playing,
            focusRequestId: 0,
            focusLineIndex: null,
            fallbackCandidateFor: (_) => null,
            onPreviewLine: null,
            onInsertedLineFocus: (_) {},
            onSelectLine: (index) => setState(() => selected = index),
            onUpdateLine: (_, _) {},
            onDeleteLine: (_) {},
            jump: widget.jump,
          ),
        ),
      ),
    );
  }
}

void main() {
  group('the 跳到行 dialog', () {
    final document = _document(120);
    int? picked;
    var closed = false;

    Future<void> open(WidgetTester tester, {int? current}) async {
      picked = null;
      closed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await showLyricJumpToLineDialog(
                  context,
                  document: document,
                  current: current,
                );
                closed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    FilledButton confirm(WidgetTester tester) => tester.widget<FilledButton>(
      find.byKey(LyricJumpToLineDialog.confirmKey),
    );

    testWidgets('starts from the selected row and shows it', (tester) async {
      await open(tester, current: 4);
      final field = tester.widget<TextField>(
        find.byKey(LyricJumpToLineDialog.inputKey),
      );
      expect(field.controller!.text, '5');
      expect(field.controller!.selection.extentOffset, 1);
      expect(find.text('第 5 行 · 0:17.00'), findsOneWidget);
      expect(find.text('row 5'), findsOneWidget);
    });

    testWidgets('a row past the end explains and cannot be confirmed', (
      tester,
    ) async {
      await open(tester);
      expect(confirm(tester).onPressed, isNull);
      await tester.enterText(find.byKey(LyricJumpToLineDialog.inputKey), '200');
      await tester.pump();
      expect(find.text('没有第 200 行，这首歌一共 120 行'), findsOneWidget);
      expect(confirm(tester).onPressed, isNull);
    });

    testWidgets('a time finds its row and Enter jumps there', (tester) async {
      await open(tester);
      await tester.enterText(
        find.byKey(LyricJumpToLineDialog.inputKey),
        '1:05',
      );
      await tester.pump();
      expect(find.text('1:05.00 → 第 17 行 · 1:05.00 开始'), findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(picked, 16);
    });

    testWidgets('the button jumps, cancel does not', (tester) async {
      await open(tester);
      await tester.enterText(find.byKey(LyricJumpToLineDialog.inputKey), '80');
      await tester.pump();
      await tester.tap(find.byKey(LyricJumpToLineDialog.confirmKey));
      await tester.pumpAndSettle();
      expect(picked, 79);

      await open(tester);
      await tester.enterText(find.byKey(LyricJumpToLineDialog.inputKey), '80');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(picked, isNull);
    });

    test('the menu names the shortcut only where there is a keyboard', () {
      expect(
        LyricJumpStrings.menuDetail(TargetPlatform.windows),
        contains('Ctrl+G'),
      );
      expect(
        LyricJumpStrings.menuDetail(TargetPlatform.macOS),
        contains('⌘G'),
      );
      expect(
        LyricJumpStrings.menuDetail(TargetPlatform.android),
        LyricJumpStrings.menuDetailTouch,
      );
    });
  });

  group('the list', () {
    late LyricLineJumpController jump;

    setUp(() => jump = LyricLineJumpController());
    tearDown(() => jump.dispose());

    ScrollPosition position(WidgetTester tester) => tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;

    bool onScreen(WidgetTester tester, String text) {
      final finder = find.text(text);
      if (finder.evaluate().isEmpty) return false;
      final rect = tester.getRect(finder);
      final list = tester.getRect(find.byType(ListView));
      return rect.top >= list.top && rect.bottom <= list.bottom;
    }

    testWidgets('a jump scrolls far down to the row', (tester) async {
      await tester.pumpWidget(_Host(document: _document(120), jump: jump));
      expect(onScreen(tester, 'row 100'), isFalse);

      jump.jumpTo(99);
      await tester.pumpAndSettle();
      expect(onScreen(tester, 'row 100'), isTrue);
      expect(tester.takeException(), isNull);

      // And back up again.
      jump.jumpTo(2);
      await tester.pumpAndSettle();
      expect(onScreen(tester, 'row 3'), isTrue);
    });

    testWidgets('a jump clears a search that hides the row', (tester) async {
      await tester.pumpWidget(_Host(document: _document(120), jump: jump));
      await tester.enterText(find.byType(TextField), 'row 5');
      await tester.pump();
      expect(find.text('row 100'), findsNothing);

      jump.jumpTo(99);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(onScreen(tester, 'row 100'), isTrue);
    });

    testWidgets('the arrow keys keep the selected row on screen', (
      tester,
    ) async {
      await tester.pumpWidget(_Host(document: _document(60), jump: jump));
      await tester.tap(find.text('row 1'));
      // The row also listens for a double tap.
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
      for (var step = 0; step < 15; step++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
      }
      expect(onScreen(tester, 'row 16'), isTrue);
      expect(onScreen(tester, 'row 1'), isFalse);
    });

    group('following playback', () {
      Future<_HostState> follow(WidgetTester tester, {int playing = 0}) async {
        await tester.pumpWidget(
          _Host(
            document: _document(120),
            jump: jump,
            followPlayback: true,
            playing: playing,
          ),
        );
        await tester.pumpAndSettle();
        return tester.state<_HostState>(find.byType(_Host));
      }

      Future<void> scrollAway(WidgetTester tester) async {
        await tester.drag(find.byType(ListView), const Offset(0, -900));
        await tester.pumpAndSettle();
      }

      testWidgets('scrolling by hand pauses it; the button comes back', (
        tester,
      ) async {
        final host = await follow(tester);
        await scrollAway(tester);
        final away = position(tester).pixels;
        expect(away, greaterThan(500));

        host.play(1);
        await tester.pumpAndSettle();
        expect(position(tester).pixels, away);
        expect(find.byKey(LyricListPane.resumeFollowKey), findsOneWidget);
        expect(find.text(LyricListPane.resumeFollowLabel(1)), findsOneWidget);

        await tester.tap(find.byKey(LyricListPane.resumeFollowKey));
        await tester.pumpAndSettle();
        expect(position(tester).pixels, 0);
        expect(find.byKey(LyricListPane.resumeFollowKey), findsNothing);
      });

      testWidgets('it picks up again after a quiet spell', (tester) async {
        final host = await follow(tester);
        await scrollAway(tester);
        final away = position(tester).pixels;

        host.play(80);
        await tester.pumpAndSettle();
        expect(position(tester).pixels, away);

        await tester.pump(LyricListNavigation.followPause);
        await tester.pumpAndSettle();
        expect(onScreen(tester, 'row 81'), isTrue);
        expect(find.byKey(LyricListPane.resumeFollowKey), findsNothing);
      });

      testWidgets('a paused song does not pull the list back', (tester) async {
        await follow(tester);
        await scrollAway(tester);
        final away = position(tester).pixels;
        expect(find.byKey(LyricListPane.resumeFollowKey), findsNothing);

        await tester.pump(LyricListNavigation.followPause);
        await tester.pumpAndSettle();
        expect(position(tester).pixels, away);
      });

      testWidgets('a jump is not undone by the next line', (tester) async {
        final host = await follow(tester);
        jump.jumpTo(99);
        await tester.pumpAndSettle();
        host.play(1);
        await tester.pumpAndSettle();
        expect(onScreen(tester, 'row 100'), isTrue);
      });
    });
  });
}

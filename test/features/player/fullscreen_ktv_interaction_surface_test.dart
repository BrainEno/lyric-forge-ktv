import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/fullscreen_ktv_interaction_surface.dart';

void main() {
  testWidgets('controls hide after idle and reveal on tap', (tester) async {
    await tester.pumpWidget(
      _TestApp(
        hideDelay: const Duration(milliseconds: 100),
        onExit: () {},
      ),
    );

    expect(find.text('controls-visible'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('controls-hidden'), findsOneWidget);

    await tester.tapAt(const Offset(20, 20));
    // The surface also handles `onDoubleTap`, so a single tap only resolves
    // after the double-tap timeout.
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('controls-visible'), findsOneWidget);

    // Dispose the surface so its idle-hide timer does not outlive the test.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('escape exits fullscreen KTV', (tester) async {
    var exits = 0;
    await tester.pumpWidget(
      _TestApp(
        hideDelay: const Duration(seconds: 30),
        onExit: () => exits += 1,
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(exits, 1);
  });

  testWidgets('double tap exits fullscreen KTV', (tester) async {
    var exits = 0;
    await tester.pumpWidget(
      _TestApp(
        hideDelay: const Duration(seconds: 30),
        onExit: () => exits += 1,
      ),
    );

    // Two taps inside the double-tap timeout trigger `onDoubleTap`.
    await tester.tap(find.text('lyrics'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('lyrics'));
    await tester.pump();

    expect(exits, 1);

    // Let the double-tap recognizer's minimum-interval timer expire, then
    // dispose the surface so its idle-hide timer does not outlive the test.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(const SizedBox());
  });

  group('screen reader (audit A-04)', () {
    Semantics surfaceSemantics(WidgetTester tester) {
      return tester.widget<Semantics>(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label ==
                  FullscreenKtvInteractionSurface.semanticsLabel,
        ),
      );
    }

    VoidCallback action(Semantics semantics, String label) {
      final actions = semantics.properties.customSemanticsActions!;
      return actions[CustomSemanticsAction(label: label)]!;
    }

    testWidgets('the surface is named and offers both gestures as actions', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _TestApp(hideDelay: const Duration(seconds: 30), onExit: () {}),
      );

      expect(
        find.bySemanticsLabel(FullscreenKtvInteractionSurface.semanticsLabel),
        findsOneWidget,
      );
      final semantics = surfaceSemantics(tester);
      final actions = semantics.properties.customSemanticsActions!;
      expect(actions.keys.map((action) => action.label), [
        FullscreenKtvInteractionSurface.showControlsAction,
        FullscreenKtvInteractionSurface.exitAction,
      ]);
      // The lyrics inside are still read, not swallowed by the label.
      expect(find.bySemanticsLabel(RegExp('lyrics')), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      handle.dispose();
    });

    testWidgets('the show-controls action brings faded controls back', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _TestApp(hideDelay: const Duration(milliseconds: 100), onExit: () {}),
      );
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.text('controls-hidden'), findsOneWidget);

      action(
        surfaceSemantics(tester),
        FullscreenKtvInteractionSurface.showControlsAction,
      )();
      await tester.pump();
      expect(find.text('controls-visible'), findsOneWidget);

      // They fade again after the usual idle delay.
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.text('controls-hidden'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      handle.dispose();
    });

    testWidgets('the exit action leaves without a keyboard', (tester) async {
      final handle = tester.ensureSemantics();
      var exits = 0;
      await tester.pumpWidget(
        _TestApp(
          hideDelay: const Duration(seconds: 30),
          onExit: () => exits += 1,
        ),
      );

      action(
        surfaceSemantics(tester),
        FullscreenKtvInteractionSurface.exitAction,
      )();
      expect(exits, 1);

      await tester.pumpWidget(const SizedBox());
      handle.dispose();
    });

    test('the action map pairs each label with its callback', () {
      final calls = <String>[];
      final actions = FullscreenKtvInteractionSurface.semanticsActions(
        onShowControls: () => calls.add('show'),
        onExit: () => calls.add('exit'),
      );
      for (final callback in actions.values) {
        callback();
      }
      expect(calls, ['show', 'exit']);
    });
  });
}

class _TestApp extends StatelessWidget {
  final Duration hideDelay;
  final VoidCallback onExit;

  const _TestApp({
    required this.hideDelay,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: FullscreenKtvInteractionSurface(
          controlsHideDelay: hideDelay,
          onExit: onExit,
          builder: (context, controlsVisible) {
            return SizedBox.expand(
              child: Column(
                children: [
                  Text(controlsVisible ? 'controls-visible' : 'controls-hidden'),
                  const Expanded(child: Center(child: Text('lyrics'))),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
